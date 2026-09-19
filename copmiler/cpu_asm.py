#!/usr/bin/env python3
"""Assembler for the 4-bit CPU described in verilog/docs/ISA.md.

The assembler deliberately implements only the existing ISA. It emits a 256-byte
memory image by default, so the resulting file can be loaded directly into the
CPU instruction memory.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Mapping, Optional, Sequence, Tuple

MEMORY_SIZE = 256
MIN_BRANCH_DISP = -8
MAX_BRANCH_DISP = 7

LABEL_NAME = r"[A-Za-z_][A-Za-z0-9_.$]*"
LABEL_RE = re.compile(rf"^[ \t]*({LABEL_NAME}):")
LABEL_EXPR_RE = re.compile(
    rf"^[ \t]*({LABEL_NAME})[ \t]*([+-])[ \t]*"
    r"(0[xX][0-9A-Fa-f]+|0[bB][01]+|\d+)[ \t]*$"
)
INTEGER_RE = re.compile(
    r"^([+-]?)(0[xX][0-9A-Fa-f]+|0[bB][01]+|\d+)$"
)
class AsmError(Exception):
    """An input error with an optional source location."""

    def __init__(self, message: str, location: Optional["SourceLocation"] = None):
        super().__init__(message)
        self.message = message
        self.location = location

    def __str__(self) -> str:
        if self.location is None:
            return self.message
        return f"{self.location.format()}: {self.message}"


@dataclass(frozen=True)
class SourceLocation:
    path: str
    line: int
    text: str

    def format(self) -> str:
        return f"{self.path}:{self.line}"


@dataclass(frozen=True)
class Entry:
    address: int
    value: int
    location: SourceLocation
    text: str


@dataclass(frozen=True)
class InstructionSpec:
    opcode: int
    operand_kind: str  # none, immediate, port, branch


INSTRUCTIONS: Mapping[str, InstructionSpec] = {
    "NOP": InstructionSpec(0x0, "none"),
    "LDI0": InstructionSpec(0x1, "immediate"),
    "LDI1": InstructionSpec(0x2, "immediate"),
    "ADD": InstructionSpec(0x3, "none"),
    "SUB": InstructionSpec(0x4, "none"),
    "AND": InstructionSpec(0x5, "none"),
    "XOR": InstructionSpec(0x6, "none"),
    "JMP": InstructionSpec(0x7, "branch"),
    "JC": InstructionSpec(0x8, "branch"),
    "JV": InstructionSpec(0x9, "branch"),
    "IN": InstructionSpec(0xA, "port"),
    "OUT": InstructionSpec(0xB, "port"),
    "MOV01": InstructionSpec(0xC, "none"),
    "MOV10": InstructionSpec(0xD, "none"),
    "HALT": InstructionSpec(0xE, "none"),
}


@dataclass
class ParsedInstruction:
    location: SourceLocation
    address: int
    mnemonic: str
    args: List[str]


class Program:
    """Resolved instruction bytes and labels."""

    def __init__(self) -> None:
        self._entries: Dict[int, Entry] = {}
        self.labels: Dict[str, int] = {}

    def put(
        self,
        address: int,
        value: int,
        location: SourceLocation,
        text: str,
    ) -> None:
        if not 0 <= address < MEMORY_SIZE:
            raise AsmError(f"address {address} is outside 0..255", location)
        if not 0 <= value <= 0xFF:
            raise AsmError(f"value {value} is outside 0..255", location)
        if address in self._entries:
            old = self._entries[address]
            raise AsmError(
                f"address 0x{address:02X} is already defined at "
                f"{old.location.format()}",
                location,
            )
        self._entries[address] = Entry(address, value, location, text)

    @property
    def entries(self) -> List[Entry]:
        return [self._entries[address] for address in sorted(self._entries)]

    @property
    def highest_address(self) -> Optional[int]:
        if not self._entries:
            return None
        return max(self._entries)

    def image(self, padding: int = 0x00) -> bytes:
        """Return a full 256-byte memory image."""
        if not 0 <= padding <= 0xFF:
            raise ValueError("padding must be in 0..255")
        data = bytearray([padding]) * MEMORY_SIZE
        for entry in self._entries.values():
            data[entry.address] = entry.value
        return bytes(data)

    def compact_image(self, padding: int = 0x00) -> bytes:
        """Return bytes through the highest emitted address."""
        highest = self.highest_address
        if highest is None:
            return b""
        data = bytearray([padding]) * (highest + 1)
        for entry in self._entries.values():
            data[entry.address] = entry.value
        return bytes(data)

    def to_mem(self, compact: bool = True, padding: int = 0x00) -> str:
        """Return a $readmemh-compatible hexadecimal memory file."""
        if compact:
            entries = self.entries
        else:
            image = self.image(padding)
            entries = [
                Entry(address, image[address], SourceLocation("<image>", 0, ""), "")
                for address in range(MEMORY_SIZE)
            ]
        if not entries:
            return ""

        lines: List[str] = []
        current_address: Optional[int] = None
        for entry in entries:
            if entry.address != current_address:
                lines.append(f"@{entry.address:02X}")
                current_address = entry.address
            lines.append(f"{entry.value:02X}")
        return "\n".join(lines) + "\n"

    def to_hex(self, compact: bool = True, padding: int = 0x00) -> str:
        """Return an Intel HEX representation of the emitted bytes."""
        if compact:
            entries = self.entries
        else:
            image = self.image(padding)
            entries = [
                Entry(address, image[address], SourceLocation("<image>", 0, ""), "")
                for address in range(MEMORY_SIZE)
            ]
        if not entries:
            return ":00000001FF\n"

        records: List[str] = []
        index = 0
        while index < len(entries):
            start = entries[index].address
            data = bytearray()
            expected = start
            while index < len(entries) and entries[index].address == expected and len(data) < 16:
                data.append(entries[index].value)
                index += 1
                expected += 1
            records.append(_hex_record(start, bytes(data)))
        records.append(":00000001FF")
        return "\n".join(records) + "\n"

    def listing(self) -> str:
        lines: List[str] = []
        for entry in self.entries:
            source = entry.text.strip()
            suffix = f"  ; {source}" if source else ""
            lines.append(f"{entry.address:04X}: {entry.value:02X}{suffix}")
        return "\n".join(lines) + "\n"


def _hex_record(address: int, data: bytes) -> str:
    payload = bytearray(
        [
            len(data),
            (address >> 8) & 0xFF,
            address & 0xFF,
            0x00,
        ]
    )
    payload.extend(data)
    checksum = (-sum(payload)) & 0xFF
    payload.append(checksum)
    return ":" + "".join(f"{value:02X}" for value in payload)


def _strip_comments(text: str) -> str:
    """Remove ;, #, and // comments while preserving quoted text."""
    result: List[str] = []
    quote: Optional[str] = None
    index = 0
    while index < len(text):
        char = text[index]
        if quote is not None:
            result.append(char)
            if char == "\\":
                result.append(text[index + 1] if index + 1 < len(text) else "")
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char in ("'", '"'):
            quote = char
            result.append(char)
            index += 1
            continue
        if char == ";":
            break
        if char == "#":
            break
        if char == "/" and index + 1 < len(text) and text[index + 1] == "/":
            break
        result.append(char)
        index += 1
    return "".join(result)


def _split_arguments(text: str) -> List[str]:
    if not text.strip():
        return []
    return [part.strip() for part in text.split(",") if part.strip()]


def _split_values(text: str) -> List[str]:
    normalized = text.replace(",", " ")
    return [part for part in normalized.split() if part]


def _parse_integer(
    text: str,
    location: Optional[SourceLocation] = None,
    *,
    allow_negative: bool = True,
    constants: Optional[Mapping[str, int]] = None,
) -> int:
    value_text = text.strip()
    if constants and value_text.upper() in constants:
        return constants[value_text.upper()]

    match = INTEGER_RE.fullmatch(value_text)
    if match is None:
        raise AsmError(f"invalid integer expression '{text}'", location)
    sign_text, number_text = match.groups()
    if number_text.lower().startswith("0x"):
        value = int(number_text, 16)
    elif number_text.lower().startswith("0b"):
        value = int(number_text, 2)
    else:
        value = int(number_text, 10)
    if sign_text == "-":
        value = -value
    if not allow_negative and value < 0:
        raise AsmError(f"negative value is not allowed: '{text}'", location)
    return value


def _require_argument_count(
    mnemonic: str,
    args: Sequence[str],
    expected: int,
    location: SourceLocation,
) -> None:
    if len(args) != expected:
        raise AsmError(
            f"{mnemonic} expects {expected} operand(s), got {len(args)}",
            location,
        )


def _parse_port(text: str, location: SourceLocation) -> int:
    value = text.strip()
    upper = value.upper()
    if upper in ("PORT0", "0"):
        return 0
    if upper in ("PORT1", "1"):
        return 1
    raise AsmError(f"invalid I/O port '{value}'; expected PORT0 or PORT1", location)


def _resolve_label(
    name: str,
    labels: Mapping[str, int],
    location: SourceLocation,
) -> int:
    key = name.upper()
    if key not in labels:
        raise AsmError(f"undefined label '{name}'", location)
    return labels[key]


def _target_from_expression(
    expression: str,
    labels: Mapping[str, int],
    constants: Mapping[str, int],
    location: SourceLocation,
) -> int:
    value = expression.strip()
    match = LABEL_EXPR_RE.fullmatch(value)
    if match is not None:
        label, sign, offset_text = match.groups()
        offset = _parse_integer(offset_text, location)
        target = _resolve_label(label, labels, location)
        return target + (-offset if sign == "-" else offset)

    if re.fullmatch(LABEL_NAME, value):
        return _resolve_label(value, labels, location)
    return _parse_integer(value, location, constants=constants)


def _encode_branch(
    argument: str,
    address: int,
    labels: Mapping[str, int],
    constants: Mapping[str, int],
    location: SourceLocation,
) -> int:
    value = argument.strip()
    absolute = value.startswith("@")
    if absolute:
        value = value[1:].strip()
        if not value:
            raise AsmError("branch target is empty", location)
        target = _target_from_expression(value, labels, constants, location)
        displacement = target - (address + 1)
    else:
        label_match = LABEL_EXPR_RE.fullmatch(value)
        if label_match is not None or re.fullmatch(LABEL_NAME, value):
            target = _target_from_expression(value, labels, constants, location)
            displacement = target - (address + 1)
        else:
            displacement = _parse_integer(value, location)
            target = address + 1 + displacement

    if not MIN_BRANCH_DISP <= displacement <= MAX_BRANCH_DISP:
        raise AsmError(
            f"branch displacement {displacement} is outside signed range "
            f"{MIN_BRANCH_DISP}..{MAX_BRANCH_DISP}",
            location,
        )
    target = address + 1 + displacement
    if not 0 <= target < MEMORY_SIZE:
        target_text = str(target) if target < 0 else f"0x{target:02X}"
        raise AsmError(
            f"branch target {target_text} is outside memory range 0x00..0xFF",
            location,
        )
    return displacement & 0x0F


def _encode_instruction(
    instruction: ParsedInstruction,
    labels: Mapping[str, int],
    constants: Mapping[str, int],
) -> int:
    location = instruction.location
    mnemonic = instruction.mnemonic.upper()
    spec = INSTRUCTIONS.get(mnemonic)
    if spec is None:
        if mnemonic == "RESERVED":
            raise AsmError(
                "RESERVED is not an assembler instruction; use .db 0xF0 only when "
                "a reserved byte is explicitly required",
                location,
            )
        raise AsmError(f"unknown instruction '{instruction.mnemonic}'", location)

    kind = spec.operand_kind
    if kind == "none":
        _require_argument_count(mnemonic, instruction.args, 0, location)
        return spec.opcode << 4

    _require_argument_count(mnemonic, instruction.args, 1, location)
    argument = instruction.args[0]
    if kind == "immediate":
        value = _parse_integer(
            argument,
            location,
            allow_negative=False,
            constants=constants,
        )
        if not 0 <= value <= 0x0F:
            raise AsmError(
                f"immediate {value} is outside range 0..15",
                location,
            )
        return (spec.opcode << 4) | (value & 0x0F)
    if kind == "port":
        return (spec.opcode << 4) | _parse_port(argument, location)
    if kind == "branch":
        return (spec.opcode << 4) | _encode_branch(
            argument,
            instruction.address,
            labels,
            constants,
            location,
        )
    raise AssertionError(f"unhandled operand kind: {kind}")


class Assembler:
    """Two-pass assembler implementation."""

    def __init__(self, origin: int = 0) -> None:
        if not 0 <= origin < MEMORY_SIZE:
            raise AsmError(f"origin {origin} is outside memory range 0..255")
        self.origin = origin
        self.pc = origin
        self.labels: Dict[str, int] = {}
        self.constants: Dict[str, int] = {}
        self.instructions: List[ParsedInstruction] = []
        self.program = Program()

    def assemble_text(self, text: str, source_name: str = "<string>") -> Program:
        self.pc = self.origin
        self.labels.clear()
        self.constants.clear()
        self.instructions.clear()
        self.program = Program()

        for line_number, raw_line in enumerate(text.splitlines(), start=1):
            location = SourceLocation(source_name, line_number, raw_line)
            code = _strip_comments(raw_line).strip()
            if not code:
                continue

            while True:
                label_match = LABEL_RE.match(code)
                if label_match is None:
                    break
                self._define_label(label_match.group(1), location)
                code = code[label_match.end():].strip()

            if not code:
                continue
            if code.startswith("."):
                self._parse_directive(code[1:], location)
                continue

            parts = code.split(None, 1)
            mnemonic = parts[0].upper()
            args_text = parts[1].strip() if len(parts) == 2 else ""
            args = _split_arguments(args_text)
            # A trailing colon is convenient for inline labels such as "JMP LOOP:".
            args = [arg[:-1] if arg.endswith(":") else arg for arg in args]
            self.instructions.append(
                ParsedInstruction(location, self.pc, mnemonic, args)
            )
            self.pc += 1
            if self.pc > MEMORY_SIZE:
                raise AsmError(
                    f"program exceeds memory: next address is 0x{self.pc:02X}",
                    location,
                )

        for instruction in self.instructions:
            value = _encode_instruction(
                instruction,
                self.labels,
                self.constants,
            )
            self.program.put(
                instruction.address,
                value,
                instruction.location,
                raw_instruction_text(text, instruction.location.line),
            )
        self.program.labels = dict(self.labels)
        return self.program

    def _define_label(self, name: str, location: SourceLocation) -> None:
        key = name.upper()
        if key in self.labels:
            raise AsmError(f"duplicate label '{name}'", location)
        if not 0 <= self.pc < MEMORY_SIZE:
            raise AsmError(
                f"label '{name}' is at address 0x{self.pc:02X}, outside memory",
                location,
            )
        self.labels[key] = self.pc

    def _parse_directive(self, directive_text: str, location: SourceLocation) -> None:
        parts = directive_text.split(None, 1)
        if not parts:
            raise AsmError("empty directive", location)
        directive = parts[0].lower()
        body = parts[1].strip() if len(parts) == 2 else ""

        if directive == "org":
            args = _split_values(body)
            _require_argument_count(".org", args, 1, location)
            address = _parse_integer(
                args[0],
                location,
                allow_negative=False,
                constants=self.constants,
            )
            if not 0 <= address < MEMORY_SIZE:
                raise AsmError(
                    f".org address {address} is outside range 0..255",
                    location,
                )
            self.pc = address
            return

        if directive in ("fill", "space"):
            args = _split_values(body)
            if len(args) not in (1, 2):
                raise AsmError(
                    f".{directive} expects count [, value], got {len(args)}",
                    location,
                )
            count = _parse_integer(
                args[0],
                location,
                allow_negative=False,
                constants=self.constants,
            )
            value = (
                _parse_integer(
                    args[1],
                    location,
                    allow_negative=False,
                    constants=self.constants,
                )
                if len(args) == 2
                else 0
            )
            if not 0 <= value <= 0xFF:
                raise AsmError(f"fill value {value} is outside range 0..255", location)
            for offset in range(count):
                address = self.pc + offset
                if not 0 <= address < MEMORY_SIZE:
                    raise AsmError(
                        f".{directive} exceeds memory at address 0x{address:02X}",
                        location,
                    )
                self.program.put(address, value, location, directive_text)
            self.pc += count
            if self.pc > MEMORY_SIZE:
                raise AsmError(f".{directive} exceeds memory", location)
            return

        if directive == "db":
            values = _split_values(body)
            if not values:
                raise AsmError(".db expects at least one byte", location)
            for value_text in values:
                value = _parse_integer(
                    value_text,
                    location,
                    allow_negative=False,
                    constants=self.constants,
                )
                if not 0 <= value <= 0xFF:
                    raise AsmError(
                        f".db value {value} is outside range 0..255",
                        location,
                    )
                self.program.put(self.pc, value, location, directive_text)
                self.pc += 1
                if self.pc > MEMORY_SIZE:
                    raise AsmError(".db exceeds memory", location)
            return

        if directive == "equ":
            match = re.match(
                rf"^[ \t]*({LABEL_NAME})[ \t]*(?:,|=)[ \t]*(.+?)[ \t]*$",
                body,
            )
            if match is None:
                raise AsmError(
                    "syntax: .equ NAME, expression or .equ NAME = expression",
                    location,
                )
            name, expression = match.groups()
            key = name.upper()
            if key in self.constants:
                raise AsmError(f"duplicate constant '{name}'", location)
            value = _parse_integer(
                expression,
                location,
                allow_negative=True,
                constants=self.constants,
            )
            self.constants[key] = value
            return

        raise AsmError(f"unknown directive '.{directive}'", location)


def raw_instruction_text(text: str, line_number: int) -> str:
    lines = text.splitlines()
    if 1 <= line_number <= len(lines):
        return lines[line_number - 1]
    return ""


def assemble_text(text: str, source_name: str = "<string>", origin: int = 0) -> Program:
    """Assemble source text and return a resolved Program."""
    if text.startswith("\ufeff"):
        text = text[1:]
    return Assembler(origin=origin).assemble_text(text, source_name)


def assemble_file(path: Path, origin: Optional[int] = None) -> Program:
    """Assemble an UTF-8 source file."""
    source = path.read_text(encoding="utf-8")
    return assemble_text(source, str(path), origin=0 if origin is None else origin)


def _parse_cli_integer(text: str) -> int:
    try:
        return _parse_integer(text)
    except AsmError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def _output_paths(
    input_path: Path,
    output: Optional[Path],
    output_format: str,
) -> List[Tuple[Path, str]]:
    if output_format != "all":
        suffix = {
            "bin": ".bin",
            "mem": ".mem",
            "hex": ".hex",
        }[output_format]
        path = output if output is not None else input_path.with_suffix(suffix)
        return [(path, output_format)]

    base = output if output is not None else input_path.with_suffix("")
    return [
        (base.with_suffix(".bin"), "bin"),
        (base.with_suffix(".mem"), "mem"),
        (base.with_suffix(".hex"), "hex"),
    ]


def _write_output(
    path: Path,
    output_format: str,
    program: Program,
    compact: bool,
    padding: int,
) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    if output_format == "bin":
        data = program.compact_image(padding) if compact else program.image(padding)
        path.write_bytes(data)
        return len(data)
    if output_format == "mem":
        data_text = program.to_mem(compact=compact, padding=padding)
        path.write_text(data_text, encoding="ascii")
        return len(data_text.encode("ascii"))
    if output_format == "hex":
        data_text = program.to_hex(compact=compact, padding=padding)
        path.write_text(data_text, encoding="ascii")
        return len(data_text.encode("ascii"))
    raise AssertionError(f"unknown output format {output_format}")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Assemble the 4-bit CPU ISA into a binary memory image."
    )
    parser.add_argument("input", type=Path, help="input .asm file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="output file; default is the input name with a format suffix",
    )
    parser.add_argument(
        "--format",
        choices=("bin", "mem", "hex", "all"),
        default="bin",
        help="output format (default: bin)",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="omit trailing padding bytes; raw .bin then may be shorter than 256 bytes",
    )
    parser.add_argument(
        "--padding",
        type=_parse_cli_integer,
        default=0x00,
        help="padding byte for holes and unused memory (default: 0x00)",
    )
    parser.add_argument(
        "--origin",
        type=_parse_cli_integer,
        default=None,
        help="initial program counter, decimal or 0x-prefixed",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="print an address/byte listing",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate and assemble without writing output files",
    )
    parser.add_argument(
        "--version",
        action="version",
        version="cpu_asm 1.0",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    if not 0 <= args.padding <= 0xFF:
        parser.error("--padding must be in 0..255")
    if args.origin is not None and not 0 <= args.origin < MEMORY_SIZE:
        parser.error("--origin must be in 0..255")

    try:
        program = assemble_file(args.input, origin=args.origin)
    except (AsmError, OSError, UnicodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.list:
        print(program.listing(), end="")

    if args.check:
        highest = program.highest_address
        highest_text = "empty" if highest is None else f"0x{highest:02X}"
        print(
            f"OK: {len(program.entries)} instruction bytes, "
            f"highest address {highest_text}"
        )
        return 0

    try:
        for path, output_format in _output_paths(
            args.input,
            args.output,
            args.format,
        ):
            size = _write_output(
                path,
                output_format,
                program,
                args.compact,
                args.padding,
            )
            print(f"wrote {path} ({size} bytes)")
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
