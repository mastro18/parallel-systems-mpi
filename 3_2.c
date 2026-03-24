#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <mpi.h>
#include <stdbool.h>
#include <string.h>

static double timer(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

typedef struct {
    int *values;
    int *col_ind;
    int *nz_in_row;
    int non_zero_values;
    int n;
} CSR_Matrix;

void createCSR(CSR_Matrix *csr, int **matrix, int n, int *offsets) {

    int count = 0;
    for (int i = 0; i < n; i++) {
        int count2 = 0;
        for (int j = 0; j < n; j++) {
            if (matrix[i][j] != 0) {
                csr->values[count] = matrix[i][j];
                csr->col_ind[count] = j;
                count++;
                count2++;
            }
        }
        csr->nz_in_row[i] = count2;
    }

    //Offset of which values belong to which row.
    offsets[0] = 0;
    for (int i = 0; i < n; i++) {
        offsets[i + 1] = offsets[i] + csr->nz_in_row[i];
    }
}

int main(int argc, char *argv[]) {
    int rank, num_procs;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &num_procs);

    if (argc != 4) {
        if (rank == 0) {
            printf("Usage: %s (matrix_size) (sparsity_percent) (iterations)\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    int n = atoi(argv[1]);              //Matrix size (n x n).
    int sparsity = atoi(argv[2]);       //Percentage of zeros.
    int iterations = atoi(argv[3]);     //Number of iterations.

    if (n <= 0 || sparsity < 0 || sparsity > 100 || iterations <= 0) {
        if (rank == 0) {
            printf("Invalid arguments\n");
        }
        MPI_Finalize();
        return 1;
    }

    CSR_Matrix csr;
    int **matrix = NULL;
    int *vector = malloc(sizeof(int) * n);
    int *offsets = malloc(sizeof(int) * (n + 1));
    
    double t_csr_construction = 0.0;
    double comm_t0 = 0.0, comm_t1 = 0.0, total_comm_time = 0.0;
    double t0_sparse_par = 0.0, t1_sparse_par = 0.0;
    double t0_sparse_ser = 0.0, t1_sparse_ser = 0.0;
    double t0_dense_par = 0.0, t1_dense_par = 0.0;
    double t0_dense_ser = 0.0, t1_dense_ser = 0.0;
    double total_sparse_par_time = 0.0;
    double total_sparse_ser_time = 0.0;
    double total_dense_par_time = 0.0;
    double total_dense_ser_time = 0.0;

    //Process 0: Initialize matrix, vector and create CSR.
    if (rank == 0) {
        matrix = malloc(sizeof(int*) * n);
        for (int i = 0; i < n; i++) {
            matrix[i] = malloc(sizeof(int) * n);
        }

        srand((unsigned)time(NULL));
        //Generate random values for matrix and vector.
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                if (rand() % 100 >= sparsity) {
                    matrix[i][j] = rand() % 100 - 50;
                    if (matrix[i][j] == 0) {
                        matrix[i][j] = 1;
                    }
                } else {
                    matrix[i][j] = 0;
                }
            }
        }
        for (int i = 0; i < n; i++) {
            vector[i] = rand() % 10 + 1;
        }

        //Count non-zero values.
        int non_zero_values = 0;
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                if (matrix[i][j] != 0) non_zero_values++;
            }
        }

        //Create CSR.
        double t0 = timer();
        csr.n = n;
        csr.non_zero_values = non_zero_values;
        csr.values = malloc(sizeof(int) * non_zero_values);
        csr.col_ind = malloc(sizeof(int) * non_zero_values);
        csr.nz_in_row = malloc(sizeof(int) * n);
        createCSR(&csr, matrix, n, offsets);
        double t1 = timer();

        t_csr_construction = t1 - t0;
        printf("CSR construction time: %.6f s\n", t_csr_construction);
    }

    //Calculate how many rows each process will take.
    int rows_per_proc = n / num_procs;
    int remainder = n % num_procs;
    int row_start, row_end, local_rows;

    if (rank < remainder) {
        local_rows = rows_per_proc + 1;
        row_start = rank * (rows_per_proc + 1);
    } else {
        local_rows = rows_per_proc;
        row_start = rank * rows_per_proc + remainder;
    }
    row_end = row_start + local_rows;

    MPI_Barrier(MPI_COMM_WORLD);
    comm_t0 = timer();

    MPI_Bcast(offsets, n + 1, MPI_INT, 0, MPI_COMM_WORLD);
    MPI_Bcast(vector, n, MPI_INT, 0, MPI_COMM_WORLD);

    //How many values each process will take.
    int local_nz_count = offsets[row_end] - offsets[row_start];

    int *local_values = malloc(sizeof(int) * local_nz_count);
    int *local_col_ind = malloc(sizeof(int) * local_nz_count);

    //counts: how many values to send to each process.
    //start_pos: starting position from values array to send to each process.
    int *counts = malloc(sizeof(int) * num_procs);
    int *start_pos = malloc(sizeof(int) * num_procs);
    
    counts[rank] = local_nz_count;
    start_pos[rank] = offsets[row_start];
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, counts, 1, MPI_INT, MPI_COMM_WORLD);
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, start_pos, 1, MPI_INT, MPI_COMM_WORLD);

    MPI_Scatterv(csr.values, counts, start_pos, MPI_INT, local_values, local_nz_count, MPI_INT, 0, MPI_COMM_WORLD);
    MPI_Scatterv(csr.col_ind, counts, start_pos, MPI_INT, local_col_ind, local_nz_count, MPI_INT, 0, MPI_COMM_WORLD);

    free(counts);
    free(start_pos);

    MPI_Barrier(MPI_COMM_WORLD);
    comm_t1 = timer();
    if (rank == 0) {
        total_comm_time += (comm_t1 - comm_t0);
    }

    /*START Sparse matrix-vector multiplication (parallel)*/
    int *vec_in = malloc(sizeof(int) * n);
    int *vec_out = malloc(sizeof(int) * n);
    int *local_result = malloc(sizeof(int) * local_rows);
    
    memcpy(vec_in, vector, sizeof(int) * n);

    int *recvcounts = malloc(sizeof(int) * num_procs);   //How many elements to receive from each process.
    int *recstart_pos = malloc(sizeof(int) * num_procs); //Where to place data from processes in vec_out.
    
    recstart_pos[rank] = row_start;
    recvcounts[rank] = local_rows;
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, recvcounts, 1, MPI_INT, MPI_COMM_WORLD);
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, recstart_pos, 1, MPI_INT, MPI_COMM_WORLD);

    MPI_Barrier(MPI_COMM_WORLD);
    t0_sparse_par = timer();

    for (int it = 0; it < iterations; it++) {
        for (int i = 0; i < local_rows; i++) {
            int i_row = row_start + i;
            int sum = 0;
            int start = offsets[i_row] - offsets[row_start];
            int end = offsets[i_row + 1] - offsets[row_start];
            
            for (int idx = start; idx < end; idx++) {
                sum += local_values[idx] * vec_in[local_col_ind[idx]];
            }
            local_result[i] = sum;
        }

        MPI_Allgatherv(local_result, local_rows, MPI_INT, vec_out, recvcounts, recstart_pos, MPI_INT, MPI_COMM_WORLD);

        int *temp = vec_in;
        vec_in = vec_out;
        vec_out = temp;
    }

    MPI_Barrier(MPI_COMM_WORLD);
    t1_sparse_par = timer();

    free(recvcounts);
    free(recstart_pos);

    int *sparse_result = malloc(sizeof(int) * n);
    memcpy(sparse_result, vec_in, sizeof(int) * n);
    
    if (rank == 0) {
        total_sparse_par_time = t1_sparse_par - t0_sparse_par + comm_t1 - comm_t0 + t_csr_construction;
        printf("Sparse matrix-vector multiplication (parallel): %.6f s\n", t1_sparse_par - t0_sparse_par);
        printf("Sparse matrix-vector multiplication total time(parallel) (communication + multiply + csr construction): %.6f s\n", total_sparse_par_time);
        printf("Communication time from proccess 0 to the others: %.6f s\n", comm_t1 - comm_t0);
        printf("\n");
    }

    free(vec_in);
    free(vec_out);
    free(local_result);
    free(local_values);
    free(local_col_ind);
    /*END Sparse matrix-vector multiplication (parallel)*/

    /*START Sparse matrix-vector multiplication (serial)*/
    int *sparse_result_serial = malloc(sizeof(int) * n);
    if (rank == 0) {
        int *vec_in_serial = malloc(sizeof(int) * n);
        int *vec_out_serial = malloc(sizeof(int) * n);
        memcpy(vec_in_serial, vector, sizeof(int) * n);

        t0_sparse_ser = timer();
        for (int it = 0; it < iterations; it++) {
            for (int i = 0; i < n; i++) {
                int sum = 0;
                int start = offsets[i];
                int end = offsets[i + 1];
                
                for (int idx = start; idx < end; idx++) {
                    sum += csr.values[idx] * vec_in_serial[csr.col_ind[idx]];
                }
                vec_out_serial[i] = sum;
            }
            int *temp = vec_in_serial;
            vec_in_serial = vec_out_serial;
            vec_out_serial = temp;
        }
        t1_sparse_ser = timer();
        
        memcpy(sparse_result_serial, vec_in_serial, sizeof(int) * n);
        free(vec_in_serial);
        free(vec_out_serial);
        
        total_sparse_ser_time = t1_sparse_ser - t0_sparse_ser + t_csr_construction;
        printf("Sparse matrix-vector multiplication time (serial): %.6f s\n", t1_sparse_ser - t0_sparse_ser);
        printf("Sparse matrix-vector multiplication time and csr construction time (serial): %.6f s\n", total_sparse_ser_time);
        printf("\n");
    }
    /*END Sparse matrix-vector multiplication (serial)*/

    int *local_matrix = malloc(sizeof(int) * local_rows * n); 
    int *counts_dense = malloc(sizeof(int) * num_procs);
    int *start_pos_dense = malloc(sizeof(int) * num_procs);

    MPI_Barrier(MPI_COMM_WORLD);
    comm_t0 = timer();

    counts_dense[rank] = local_rows * n;
    start_pos_dense[rank] = row_start * n;
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, counts_dense, 1, MPI_INT, MPI_COMM_WORLD);
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, start_pos_dense, 1, MPI_INT, MPI_COMM_WORLD);
    
    //Make 2d matrix to 1d for scatterv.
    int *matrix2 = NULL;
    if (rank == 0) {
        matrix2 = malloc(sizeof(int) * n * n);
        for (int i = 0; i < n; i++) {
            memcpy(&matrix2[i * n], matrix[i], sizeof(int) * n);
        }
    }
    
    MPI_Scatterv(matrix2, counts_dense, start_pos_dense, MPI_INT, local_matrix, local_rows * n, MPI_INT, 0, MPI_COMM_WORLD);

    MPI_Barrier(MPI_COMM_WORLD);
    comm_t1 = timer();
    if (rank == 0) {
        total_comm_time += (comm_t1 - comm_t0);
        free(matrix2);
    }
    free(counts_dense);
    free(start_pos_dense);

    /*START Dense matrix-vector multiplication (parallel)*/
    int *vec_in_dense = malloc(sizeof(int) * n);
    int *vec_out_dense = malloc(sizeof(int) * n);
    int *local_result_dense = malloc(sizeof(int) * local_rows);
    
    memcpy(vec_in_dense, vector, sizeof(int) * n);

    int *recvcounts_dense = malloc(sizeof(int) * num_procs);
    int *recstart_pos_dense = malloc(sizeof(int) * num_procs);

    recstart_pos_dense[rank] = row_start;
    recvcounts_dense[rank] = local_rows;
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, recvcounts_dense, 1, MPI_INT, MPI_COMM_WORLD);
    MPI_Allgather(MPI_IN_PLACE, 0, MPI_INT, recstart_pos_dense, 1, MPI_INT, MPI_COMM_WORLD);

    MPI_Barrier(MPI_COMM_WORLD);
    t0_dense_par = timer();

    for (int it = 0; it < iterations; it++) {
        for (int i = 0; i < local_rows; i++) {
            int sum = 0;
            for (int j = 0; j < n; j++) {
                sum += local_matrix[i * n + j] * vec_in_dense[j];
            }
            local_result_dense[i] = sum;
        }

        MPI_Allgatherv(local_result_dense, local_rows, MPI_INT, vec_out_dense, recvcounts_dense, recstart_pos_dense, MPI_INT, MPI_COMM_WORLD);

        int *temp = vec_in_dense;
        vec_in_dense = vec_out_dense;
        vec_out_dense = temp;
    }

    MPI_Barrier(MPI_COMM_WORLD);
    t1_dense_par = timer();

    free(recvcounts_dense);
    free(recstart_pos_dense);

    int *dense_result = malloc(sizeof(int) * n);
    memcpy(dense_result, vec_in_dense, sizeof(int) * n);

    if (rank == 0) {
        total_dense_par_time = t1_dense_par - t0_dense_par + comm_t1 - comm_t0;
        printf("Dense matrix-vector multiplication (parallel): %.6f s\n", t1_dense_par - t0_dense_par);
        printf("Dense matrix-vector multiplication total time(parallel) (communication + multiply): %.6f s\n", total_dense_par_time);
        printf("Communication time from proccess 0 to the others: %.6f s\n", comm_t1 - comm_t0);
        printf("\n");
    }
    /*END Dense matrix-vector multiplication (parallel)*/

    /*START Dense matrix-vector multiplication (serial)*/
    int *dense_result_serial = malloc(sizeof(int) * n);
    if (rank == 0) {
        int *vec_in_serial_dense = malloc(sizeof(int) * n);
        int *vec_out_serial_dense = malloc(sizeof(int) * n);
        memcpy(vec_in_serial_dense, vector, sizeof(int) * n);
        
        t0_dense_ser = timer();
        for (int it = 0; it < iterations; it++) {
            for (int i = 0; i < n; i++) {
                int sum = 0;
                for (int j = 0; j < n; j++) {
                    sum += matrix[i][j] * vec_in_serial_dense[j];
                }
                vec_out_serial_dense[i] = sum;
            }
            int *temp = vec_in_serial_dense;
            vec_in_serial_dense = vec_out_serial_dense;
            vec_out_serial_dense = temp;
        }
        t1_dense_ser = timer();
        memcpy(dense_result_serial, vec_in_serial_dense, sizeof(int) * n);

        free(vec_in_serial_dense);
        free(vec_out_serial_dense);

        total_dense_ser_time = t1_dense_ser - t0_dense_ser;
        printf("Dense matrix-vector multiplication time (serial): %.6f s\n", t1_dense_ser - t0_dense_ser);
        printf("\n");

        bool match = true;
        for (int i = 0; i < n; i++) {
            if (sparse_result[i] != dense_result[i] || sparse_result[i] != sparse_result_serial[i] || sparse_result[i] != dense_result_serial[i]) {
                match = false;
                printf("ERROR at index %d: sparse_par=%d, dense_par=%d, sparse_ser=%d, dense_ser=%d\n", i, sparse_result[i], dense_result[i], sparse_result_serial[i], dense_result_serial[i]);
                break;
            }
        }

        if (match) {
            printf("Results match!\n");
        } else {
            printf("Results do NOT match!\n");
        }
        printf("\n");

        printf("Speedup Comparisons\n");

        printf("Sparse parallel vs serial speedup: %.2fx\n", total_sparse_ser_time / total_sparse_par_time);
        printf("Dense parallel vs serial speedup: %.2fx\n", total_dense_ser_time / total_dense_par_time);
        
        if (total_dense_par_time > total_sparse_par_time) {
            printf("Parallel: sparse method faster than dense: %.2fx\n", total_dense_par_time / total_sparse_par_time);
        } else {
            printf("Parallel: dense method faster than sparse: %.2fx\n", total_sparse_par_time / total_dense_par_time);
        }
        if (total_dense_ser_time > total_sparse_ser_time) {
            printf("Serial: sparse method faster than dense: %.2fx\n", total_dense_ser_time / total_sparse_ser_time);
        } else {
            printf("Serial: dense method faster than sparse: %.2fx\n", total_sparse_ser_time / total_dense_ser_time);
        }
        free(csr.values);
        free(csr.col_ind);
        for (int i = 0; i < n; i++) {
            free(matrix[i]);
        }
        free(matrix);
    }
    free(vec_in_dense);
    free(vec_out_dense);
    free(local_result_dense);
    free(local_matrix);
    free(sparse_result);
    free(dense_result);
    free(sparse_result_serial);
    free(dense_result_serial);
    free(vector);
    free(offsets);

    MPI_Finalize();
    return 0;
}