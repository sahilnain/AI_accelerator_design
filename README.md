[![Coverage](https://img.shields.io/badge/Coverage-86.36-green?logo=codecov)]()  [![CI](https://github.com/Tfloow/cpaep2526_project/actions/workflows/ci.yml/badge.svg)]()

# CPAEP Project Template
- This project template is for the CPAEP class for the AY 2025-2026 in KU Leuven
- This template serves as a base repository for running RTL simulations.
- Preferrably, setup your work in a linux subsystem with Questasim tool.
- Please use the ESAT computers for this exercise.

# Quick Start

To run the full test with all the 3 case plus an extra large example run:

```bash
make TEST_MODULE==tb_full_test questasim-run
```

To run only one case run:

```bash
make TEST_MODULE=tb_4x4x4_sys_gemm questasim-run
```

You can also adjust the case inside `tb_4x4x4_sys_gemm`:

```verilog
parameter int unsigned SingleM = 4;
parameter int unsigned SingleK = 16;
parameter int unsigned SingleN = 64;
```
