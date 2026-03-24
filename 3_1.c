#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <mpi.h>
#include <stdbool.h>

static double timer(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char *argv[]) {
    int my_rank, num_procs;
    
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &num_procs);
    
    if (argc != 2) { 
        if (my_rank == 0) {
            printf("Usage: %s (polynomial degree)\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    long n = atol(argv[1]);
    if (n <= 0) {
        if (my_rank == 0) {
            printf("Degree must be greater than 0\n");
        }
        MPI_Finalize();
        return 1;
    }

    long pol_size = n + 1;
    long result_pol_size = 2 * n + 1;

    int *a = NULL;          //1st polynomial.
    int *b = NULL;          //2nd polynomial.
    int *res_serial = NULL; //Serial result.
    
    //Process 0: Create and initialize polynomials.
    if (my_rank == 0) {
        a = malloc(sizeof(int) * pol_size);
        b = malloc(sizeof(int) * pol_size);
        if (!a || !b) {
            printf("a or b allocation failed\n");
            MPI_Abort(MPI_COMM_WORLD, 1);
        }

        srand((unsigned)time(NULL));
        for (long i = 0; i < pol_size; i++) {
            int r;
            r = (rand() % 20) - 10;
            if (r == 0) r = 1;
            a[i] = r;
            r = (rand() % 20) - 10;
            if (r == 0) r = 1;
            b[i] = r;
        }

        //Serial multiplication.
        res_serial = calloc(result_pol_size, sizeof(int));
        if (!res_serial) { 
            printf("res_serial failed\n");
            MPI_Abort(MPI_COMM_WORLD, 1);
            return 1;
        }

        double t0 = timer();
        for (long i = 0; i <= n; i++) {
            int ai = a[i];
            for (long j = 0; j <= n; j++) {
                res_serial[i + j] += ai * b[j];
            }
        }
        double t1 = timer();
        printf("serial multiplication time: %.6f s\n", t1 - t0);
    } else {
        b = malloc(sizeof(int) * pol_size);
        if (!b) {
            printf("Process %d: b failed\n", my_rank);
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
    }
    
    double comm_t0, comm_t1, full_parallel_t0, full_parallel_t1, parallel_t0, parallel_t1, gather_t0, gather_t1;
    double total_comm_time = 0.0;
    
    MPI_Barrier(MPI_COMM_WORLD);    //Sychronize processes for more accurate time calculation.
    
    full_parallel_t0 = timer();
    
    comm_t0 = timer();
    MPI_Bcast(b, pol_size, MPI_INT, 0, MPI_COMM_WORLD);
    comm_t1 = timer();

    if (my_rank == 0) {
        total_comm_time += (comm_t1 - comm_t0);
    }
    
    //Each process will take a chunk size of a and proccess 0 will also handle remainder.
    long chunk_size = pol_size / num_procs;
    long remainder = pol_size % num_procs;
    
    //The chunk of a for each process will be stored in my_a.
    int *my_a = malloc(sizeof(int) * chunk_size);
    
    int *my_remainder = NULL;
    if (my_rank == 0 && remainder > 0) {
        my_remainder = malloc(sizeof(int) * remainder);
        for (long i = 0; i < remainder; i++) {
            my_remainder[i] = a[chunk_size * num_procs + i];
        }
    }

    MPI_Barrier(MPI_COMM_WORLD);

    comm_t0 = timer();
    MPI_Scatter(a, chunk_size, MPI_INT, my_a, chunk_size, MPI_INT, 0, MPI_COMM_WORLD);
    comm_t1 = timer();

    if (my_rank == 0) {
        total_comm_time += (comm_t1 - comm_t0);
    }
    
    //Each process partial result.
    int *my_partial = calloc(result_pol_size, sizeof(int));

    MPI_Barrier(MPI_COMM_WORLD);

    parallel_t0 = timer();

    for (long i = 0; i < chunk_size; i++) {
        long pos_start = my_rank * chunk_size + i;
        int ai = my_a[i];
        for (long j = 0; j <= n; j++) {
            my_partial[pos_start + j] += ai * b[j];
        }
    }
    
    //Process 0 also handles the remainder elements.
    if (my_rank == 0 && remainder > 0) {
        for (long i = 0; i < remainder; i++) {
            long pos_start = chunk_size * num_procs + i;
            int ai = my_remainder[i];
            for (long j = 0; j <= n; j++) {
                my_partial[pos_start + j] += ai * b[j];
            }
        }
    }

    MPI_Barrier(MPI_COMM_WORLD);

    parallel_t1 = timer();
    
    int *res_parallel = NULL;
    if (my_rank == 0) {
        res_parallel = calloc(result_pol_size, sizeof(int));
    }
    
    MPI_Barrier(MPI_COMM_WORLD);
    gather_t0 = timer();
    MPI_Reduce(my_partial, res_parallel, result_pol_size, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);
    gather_t1 = timer();

    MPI_Barrier(MPI_COMM_WORLD);
    full_parallel_t1 = timer();
    
    if (my_rank == 0) {
        printf("data send time from process 0 (broadcast + scatter): %.6f s\n", total_comm_time);
        printf("parallel multiplication time: %.6f s\n", parallel_t1 - parallel_t0);
        printf("data gathering time from processes to process 0 (reduce): %.6f s\n", gather_t1 - gather_t0);
        printf("total time including the past steps: %.6f s\n", full_parallel_t1 - full_parallel_t0);
        
        bool match = true;
        for (long i = 0; i < result_pol_size; i++) {
            if (res_serial[i] != res_parallel[i]) {
                match = false;
                break;
            }
        }
        
        if (match) {
            printf("Results match\n");
        } else {
            printf("Results do not match\n");
        }
        
        free(res_parallel);
        free(res_serial);
        free(a);
        if (my_remainder) {
            free(my_remainder);
        }
    }
    free(b);
    free(my_a);
    free(my_partial);
    
    MPI_Finalize();
    return 0;
}