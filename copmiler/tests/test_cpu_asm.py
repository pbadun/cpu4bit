import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cpu_asm import AsmError, assemble_file, assemble_text  # noqa: E402


class AssemblerTests(unittest.TestCase):
    def test_arithmetic_program(self) -> None:
        source = """
        LDI0 5
        LDI1 3
        ADD
        LDI1 1
        ADD
        MOV10
        OUT PORT0
        HALT
        """
        program = assemble_text(source, "arithmetic.asm")
        self.assertEqual(
            program.compact_image(),
            bytes.fromhex("15 23 30 21 30 D0 B0 E0"),
        )
        self.assertEqual(len(program.image()), 256)
        self.assertEqual(program.image()[0:8], program.compact_image())

    def test_all_isa_mnemonics(self) -> None:
        source = """
        NOP
        LDI0 1
        LDI1 2
        ADD
        SUB
        AND
        XOR
        JMP +1
        JC +1
        JV +1
        IN PORT0
        OUT PORT1
        MOV01
        MOV10
        HALT
        """
        program = assemble_text(source, "all_isa.asm")
        self.assertEqual(
            program.compact_image(),
            bytes.fromhex("00 11 22 30 40 50 60 71 81 91 A0 B1 C0 D0 E0"),
        )

    def test_label_branch_uses_pc_after_fetch(self) -> None:
        source = """
        LDI0 0
LOOP:   OUT PORT0
        NOP
        JMP LOOP
        """
        program = assemble_text(source, "loop.asm")
        # JMP is at address 3; PC is 4 before execution, so LOOP at 1 gives -3.
        self.assertEqual(program.compact_image(), bytes.fromhex("10 B0 00 7D"))
        self.assertEqual(program.labels["LOOP"], 1)

    def test_signed_branch_operands(self) -> None:
        program = assemble_text(
            "JMP -1\nJC -1\nJV +7\n",
            "branches.asm",
        )
        self.assertEqual(program.compact_image(), bytes.fromhex("7F 8F 97"))

    def test_absolute_branch_label(self) -> None:
        program = assemble_text(
            "START: NOP\n JMP @START\n",
            "absolute.asm",
        )
        self.assertEqual(program.compact_image(), bytes.fromhex("00 7E"))

    def test_branch_target_outside_memory_is_rejected(self) -> None:
        with self.assertRaisesRegex(AsmError, "outside memory"):
            assemble_text(".org 0xFF\nJMP +1\n", "overflow.asm")

    def test_label_branch_outside_range_is_rejected(self) -> None:
        source = """
START:  NOP
        .org 0xF8
        JMP START
        """
        with self.assertRaisesRegex(AsmError, "outside signed range"):
            assemble_text(source, "long_branch.asm")

    def test_immediate_range_is_checked(self) -> None:
        with self.assertRaisesRegex(AsmError, "outside range 0..15"):
            assemble_text("LDI0 16\n", "bad_imm.asm")
        with self.assertRaisesRegex(AsmError, "negative value"):
            assemble_text("LDI1 -1\n", "bad_imm.asm")

    def test_io_port_is_checked(self) -> None:
        with self.assertRaisesRegex(AsmError, "invalid I/O port"):
            assemble_text("IN PORT2\n", "bad_port.asm")

    def test_reserved_opcode_is_not_silently_encoded(self) -> None:
        with self.assertRaisesRegex(AsmError, "RESERVED"):
            assemble_text("RESERVED\n", "reserved.asm")

    def test_duplicate_label_is_rejected(self) -> None:
        with self.assertRaisesRegex(AsmError, "duplicate label"):
            assemble_text("A: NOP\nA: HALT\n", "labels.asm")

    def test_directives_and_padding(self) -> None:
        program = assemble_text(
            ".org 0xF8\n.db 0x12, 0x34\n.fill 2, 0x00\n",
            "data.asm",
        )
        image = program.image()
        self.assertEqual(image[0xF8:0xFC], bytes.fromhex("12 34 00 00"))
        self.assertEqual(len(image), 256)
        self.assertIn("@F8", program.to_mem())

    def test_equ_directive(self) -> None:
        program = assemble_text(
            ".equ VALUE = 15\nLDI0 VALUE\nHALT\n",
            "equ.asm",
        )
        self.assertEqual(program.compact_image(), bytes.fromhex("1F E0"))

        program = assemble_text(
            ".equ BASE = 0xF8\n.equ BYTE = 0x12\n.org BASE\n.db BYTE\nHALT\n",
            "equ_directive.asm",
        )
        self.assertEqual(program.image()[0xF8:0xFA], bytes.fromhex("12 E0"))

    def test_all_valid_examples_compile(self) -> None:
        examples = ROOT / "examples"
        expected = {
            "arithmetic.asm": "15 23 30 21 30 D0 B0 E0",
            "blink.asm": "10 B0 00 00 1F B0 00 78",
            "pwm.asm": "10 1F B0 00 10 B0 7A",
            "counter.asm": "10 B0 21 30 81 7B E0",
            "io_echo.asm": "A0 B1 7D",
            "flags.asm": "1F 21 30 82 00 00 17 21 30 92 00 00 10 B0 E0",
        }
        for path in sorted(examples.glob("*.asm")):
            if path.name == "invalid_branch.asm":
                continue
            with self.subTest(path=path.name):
                program = assemble_file(path)
                self.assertEqual(len(program.image()), 256)
                self.assertEqual(
                    program.compact_image(),
                    bytes.fromhex(expected[path.name]),
                )

    def test_invalid_example_fails(self) -> None:
        with self.assertRaisesRegex(AsmError, "outside signed range"):
            assemble_file(ROOT / "examples" / "invalid_branch.asm")

    def test_cli_check_and_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tiny.asm"
            output = Path(directory) / "tiny.bin"
            source.write_text("LDI0 1\nHALT\n", encoding="ascii")
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "cpu_asm.py"),
                    str(source),
                    "--output",
                    str(output),
                    "--check",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("OK:", result.stdout)
            self.assertFalse(output.exists())

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "cpu_asm.py"),
                    str(source),
                    "--output",
                    str(output),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            output_data = output.read_bytes()
            self.assertEqual(output_data[:2], bytes.fromhex("11 E0"))
            self.assertEqual(len(output_data), 256)
            self.assertEqual(output_data[2:], bytes(254))


if __name__ == "__main__":
    unittest.main()
