# Parallel Programming with MPI

A C/MPI project focused on distributed-memory parallel computing, performance measurement, and scalability analysis.

This project was developed for the Parallel Systems course at the University of Athens -- Department of Informatics and Telecommunications.

## Project Overview

This repository contains two MPI programs and automated benchmark scripts:

- `3_1.c`: Distributed polynomial multiplication
- `3_2.c`: Distributed sparse matrix-vector multiplication (CSR) and dense comparison
- `run_3_1_bench.sh`: Benchmark automation for Assignment 3.1
- `run_3_2_bench.sh`: Benchmark automation for Assignment 3.2
- `Makefile`: Build rules using `mpicc`

The implementation emphasizes:

- Correctness checks against serial baselines
- Explicit communication/computation timing breakdown
- Parameterized experiments with repeated runs and averaged results

## Assignment 3.1 - MPI Polynomial Multiplication (`3_1.c`)

### Problem
Compute multiplication of two random dense polynomials of degree `n` in MPI, where process 0 initializes input data and gathers the final result.

### Implementation Summary

- Process 0 generates two random non-zero integer polynomials.
- Serial baseline is computed on process 0 for validation.
- `b` is distributed with `MPI_Bcast`.
- Polynomial `a` is partitioned across processes using `MPI_Scatter`.
- Each process computes its partial contribution to the final result.
- Process 0 handles remainder elements when `n + 1` is not evenly divisible.
- Final accumulation is done with `MPI_Reduce` (sum).
- Process 0 verifies parallel output against serial output.

### Reported Metrics

- Data send time from process 0 (`broadcast + scatter`)
- Parallel compute time
- Data gathering time (`reduce`)
- Total parallel pipeline time (excluding polynomial allocation/initialization)
- Serial multiplication time (for comparison)

### Program Usage

```bash
mpiexec -n <num_processes> ./3_1 <polynomial_degree>
```

Example:

```bash
mpiexec -n 4 ./3_1 100000
```

## Assignment 3.2 - MPI Sparse Matrix-Vector Multiplication (`3_2.c`)

### Problem
Implement efficient MPI sparse matrix-vector multiplication using CSR, compare with dense representation, and analyze scalability.

### Implementation Summary

- Process 0 creates:
  - Random square matrix (`n x n`) with configurable sparsity
  - Input vector
  - CSR representation (`values`, `col_ind`, `nz_in_row`, `offsets`)
- Work distribution is row-based across processes.
- CSR data partitioning uses:
  - `MPI_Bcast` for offsets/vector
  - `MPI_Scatterv` for CSR `values` and `col_ind`
- Parallel CSR SpMV is executed for multiple iterations.
  - Output vector of iteration `k` becomes input of `k + 1`
  - Global vector reconstruction via `MPI_Allgatherv`
- Dense MPI multiplication is also executed for the same iterations and compared.
- Process 0 also runs serial sparse and serial dense baselines for correctness/performance analysis.

### Reported Metrics

- CSR construction time
- Communication time from process 0 to other processes
- Parallel sparse multiplication time
- Total sparse parallel time (communication + computation + CSR construction)
- Parallel dense multiplication time
- Total dense parallel time (communication + computation)
- Serial sparse and serial dense times
- Correctness checks and speedup summaries

### Program Usage

```bash
mpiexec -n <num_processes> ./3_2 <matrix_size> <sparsity_percent> <iterations>
```

Example:

```bash
mpiexec -n 4 ./3_2 10000 90 10
```

## Build Instructions

Build all targets:

```bash
make
```

Build a single target:

```bash
make 3_1
make 3_2
```

Clean binaries:

```bash
make clean
```

## Benchmark Automation

### 3.1 Benchmark

Run:

```bash
bash run_3_1_bench.sh
```

Default benchmark dimensions:

- Polynomial degrees: `10`, `10000`, `100000`
- MPI processes: `2`, `4`
- Repeats per configuration: `4`

Generated outputs:

- CSV: `results/csv/results_3_1.csv`
- TXT report: `results/txt/results_3_1.txt`

### 3.2 Benchmark

Run:

```bash
bash run_3_2_bench.sh
```

Default benchmark dimensions:

- Matrix sizes: `100`, `10000`
- Sparsity: `0`, `50`, `90` percent zeros
- Iterations: `5`, `15`
- MPI processes: `2`, `4`
- Repeats per configuration: `4`

Generated outputs:

- CSV: `results/csv/results_3_2.csv`
- TXT report: `results/txt/results_3_2.txt`

The scripts compute averages and aggregate statistics by parameter (size, sparsity, iterations, process count), enabling direct plotting/analysis in reports.

## Engineering Highlights

- Distributed-memory decomposition with explicit communication primitives (`Bcast`, `Scatter`, `Scatterv`, `Reduce`, `Allgatherv`)
- Clear separation of communication and computation timing
- Serial-vs-parallel verification for correctness confidence
- End-to-end experiment automation for reproducible results
- Comparative analysis of sparse vs dense representations under varying sparsity and scaling factors

## Environment Notes

- Compiler: `mpicc`
- Runtime: MPI implementation (OpenMPI/MPICH compatible)
- OS target: Linux (Ubuntu-based lab machines)

## Contributors

https://github.com/sdi2200200
