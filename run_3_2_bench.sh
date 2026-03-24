#!/bin/bash
set -euo pipefail

# Benchmark script for 3_2 (MPI Sparse Matrix CSR)
OUTDIR_CSV="results/csv"
OUTDIR_TXT="results/txt"
OUTCSV="$OUTDIR_CSV/results_3_2.csv"
OUTTXT="$OUTDIR_TXT/results_3_2.txt"
SIZES_STR="100 10000"
SPARSITY_STR="0 50 90"
ITERATIONS_STR="5 15"
PROCESSES_STR="2 4"
REPEATS=4

read -r -a SIZES <<< "$SIZES_STR"
read -r -a SPARSITY <<< "$SPARSITY_STR"
read -r -a ITERATIONS <<< "$ITERATIONS_STR"
read -r -a PROCESSES <<< "$PROCESSES_STR"

# Create output directories
mkdir -p "$OUTDIR_CSV" "$OUTDIR_TXT"

# Initialize files
echo "size,sparsity,iterations,processes,run,csr_construction_s,sparse_parallel_s,sparse_serial_s,dense_parallel_s,dense_serial_s,comm_sparse_s,comm_dense_s,match" > "$OUTCSV"
echo "3_2 Benchmark Run (MPI Sparse Matrix CSR)" > "$OUTTXT"
echo "$(date)" >> "$OUTTXT"
echo "" >> "$OUTTXT"

echo "Building 3_2..."
make 3_2 >/dev/null

for size in "${SIZES[@]}"; do
  for spar in "${SPARSITY[@]}"; do
    for iter in "${ITERATIONS[@]}"; do
      for proc in "${PROCESSES[@]}"; do
        for run in $(seq 1 $REPEATS); do
          printf "Running size=%s sparsity=%s%% iterations=%s processes=%s run=%s\n" "$size" "$spar" "$iter" "$proc" "$run"
          out=$(mpiexec -n "$proc" ./3_2 "$size" "$spar" "$iter" 2>&1 || true)

          csr_time=$(printf "%s" "$out" | grep -i "CSR construction time:" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          sparse_parallel_time=$(printf "%s" "$out" | grep -i "Sparse matrix-vector multiplication total time(parallel)" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          sparse_serial_time=$(printf "%s" "$out" | grep -i "Sparse matrix-vector multiplication time and csr construction time (serial)" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          dense_parallel_time=$(printf "%s" "$out" | grep -i "Dense matrix-vector multiplication total time(parallel)" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          dense_serial_time=$(printf "%s" "$out" | grep -i "Dense matrix-vector multiplication time (serial)" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          comm_sparse_time=$(printf "%s" "$out" | grep -i "Communication time from proccess 0 to the others:" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          comm_dense_time=$(printf "%s" "$out" | grep -i "Communication time from proccess 0 to the others:" | tail -n1 | awk -F":" '{print $2}' | awk '{print $1}')
          match=$(printf "%s" "$out" | grep -i "Results match" >/dev/null && echo yes || echo no)

          csr_time=${csr_time:-0}
          sparse_parallel_time=${sparse_parallel_time:-0}
          sparse_serial_time=${sparse_serial_time:-0}
          dense_parallel_time=${dense_parallel_time:-0}
          dense_serial_time=${dense_serial_time:-0}
          comm_sparse_time=${comm_sparse_time:-0}
          comm_dense_time=${comm_dense_time:-0}

          # Append CSV
          echo "$size,$spar,$iter,$proc,$run,$csr_time,$sparse_parallel_time,$sparse_serial_time,$dense_parallel_time,$dense_serial_time,$comm_sparse_time,$comm_dense_time,$match" >> "$OUTCSV"

          # Append human readable line
          printf "size=%s sparsity=%s%% iterations=%s processes=%s run=%s: sparse_par=%s s sparse_ser=%s s dense_par=%s s dense_ser=%s s comm_sparse=%s s comm_dense=%s s match=%s\n" \
            "$size" "$spar" "$iter" "$proc" "$run" "$sparse_parallel_time" "$sparse_serial_time" "$dense_parallel_time" "$dense_serial_time" "$comm_sparse_time" "$comm_dense_time" "$match" >> "$OUTTXT"

          # Compute number of runs so far for this (size,spar,iter,proc)
          runs_so_far=$(awk -F, -v s=$size -v sp=$spar -v it=$iter -v p=$proc '$1==s && $2==sp && $3==it && $4==p {count++} END{print count+0}' "$OUTCSV")

          # Every 4 runs print average
          if [ $(( runs_so_far % 4 )) -eq 0 ]; then
            vals=$(awk -F, -v s=$size -v sp=$spar -v it=$iter -v p=$proc '$1==s && $2==sp && $3==it && $4==p {print $6","$7","$8","$9","$10","$11","$12}' "$OUTCSV" | tail -n 4)
            if [ -n "$vals" ]; then
              sum_csr=0
              sum_sparse_par=0
              sum_sparse_ser=0
              sum_dense_par=0
              sum_dense_ser=0
              sum_comm_sparse=0
              sum_comm_dense=0
              cnt=0
              while IFS=, read -r c sp_par sp_ser d_par d_ser c_sp c_d; do
                sum_csr=$(awk -v a=$sum_csr -v b=$c 'BEGIN{printf "%.10f", a + b}')
                sum_sparse_par=$(awk -v a=$sum_sparse_par -v b=$sp_par 'BEGIN{printf "%.10f", a + b}')
                sum_sparse_ser=$(awk -v a=$sum_sparse_ser -v b=$sp_ser 'BEGIN{printf "%.10f", a + b}')
                sum_dense_par=$(awk -v a=$sum_dense_par -v b=$d_par 'BEGIN{printf "%.10f", a + b}')
                sum_dense_ser=$(awk -v a=$sum_dense_ser -v b=$d_ser 'BEGIN{printf "%.10f", a + b}')
                sum_comm_sparse=$(awk -v a=$sum_comm_sparse -v b=$c_sp 'BEGIN{printf "%.10f", a + b}')
                sum_comm_dense=$(awk -v a=$sum_comm_dense -v b=$c_d 'BEGIN{printf "%.10f", a + b}')
                cnt=$((cnt+1))
              done <<< "$vals"
              avg_csr=$(awk -v a=$sum_csr -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              avg_sparse_par=$(awk -v a=$sum_sparse_par -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              avg_sparse_ser=$(awk -v a=$sum_sparse_ser -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              avg_dense_par=$(awk -v a=$sum_dense_par -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              avg_dense_ser=$(awk -v a=$sum_dense_ser -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              avg_comm_sparse=$(awk -v a=$sum_comm_sparse -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              avg_comm_dense=$(awk -v a=$sum_comm_dense -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
              
              # Calculate speedups
              sparse_speedup=$(awk -v ser=$avg_sparse_ser -v par=$avg_sparse_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
              dense_speedup=$(awk -v ser=$avg_dense_ser -v par=$avg_dense_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
              
              printf "AVERAGE (last %d) size=%s sparsity=%s%% iterations=%s processes=%s:\n" "$cnt" "$size" "$spar" "$iter" "$proc" | tee -a "$OUTTXT"
              printf "  Sparse: parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_sparse_par" "$avg_sparse_ser" "$sparse_speedup" "$avg_comm_sparse" | tee -a "$OUTTXT"
              printf "  Dense:  parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_dense_par" "$avg_dense_ser" "$dense_speedup" "$avg_comm_dense" | tee -a "$OUTTXT"
            fi
          fi

        done
      done
      echo "" >> "$OUTTXT"
    done
  done
done

# Final averages
echo "" >> "$OUTTXT"
echo "FINAL AVERAGES:" >> "$OUTTXT"
for size in "${SIZES[@]}"; do
  for spar in "${SPARSITY[@]}"; do
    for iter in "${ITERATIONS[@]}"; do
      for proc in "${PROCESSES[@]}"; do
        vals=$(awk -F, -v s=$size -v sp=$spar -v it=$iter -v p=$proc '$1==s && $2==sp && $3==it && $4==p {print $6","$7","$8","$9","$10","$11","$12}' "$OUTCSV")
        if [ -n "$vals" ]; then
          sum_csr=0
          sum_sparse_par=0
          sum_sparse_ser=0
          sum_dense_par=0
          sum_dense_ser=0
          sum_comm_sparse=0
          sum_comm_dense=0
          cnt=0
          while IFS=, read -r c sp_par sp_ser d_par d_ser c_sp c_d; do
            sum_csr=$(awk -v a=$sum_csr -v b=$c 'BEGIN{printf "%.10f", a + b}')
            sum_sparse_par=$(awk -v a=$sum_sparse_par -v b=$sp_par 'BEGIN{printf "%.10f", a + b}')
            sum_sparse_ser=$(awk -v a=$sum_sparse_ser -v b=$sp_ser 'BEGIN{printf "%.10f", a + b}')
            sum_dense_par=$(awk -v a=$sum_dense_par -v b=$d_par 'BEGIN{printf "%.10f", a + b}')
            sum_dense_ser=$(awk -v a=$sum_dense_ser -v b=$d_ser 'BEGIN{printf "%.10f", a + b}')
            sum_comm_sparse=$(awk -v a=$sum_comm_sparse -v b=$c_sp 'BEGIN{printf "%.10f", a + b}')
            sum_comm_dense=$(awk -v a=$sum_comm_dense -v b=$c_d 'BEGIN{printf "%.10f", a + b}')
            cnt=$((cnt+1))
          done <<< "$vals"
          if [ $cnt -gt 0 ]; then
            avg_csr=$(awk -v a=$sum_csr -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            avg_sparse_par=$(awk -v a=$sum_sparse_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            avg_sparse_ser=$(awk -v a=$sum_sparse_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            avg_dense_par=$(awk -v a=$sum_dense_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            avg_dense_ser=$(awk -v a=$sum_dense_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            avg_comm_sparse=$(awk -v a=$sum_comm_sparse -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            avg_comm_dense=$(awk -v a=$sum_comm_dense -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
            
            sparse_speedup=$(awk -v ser=$avg_sparse_ser -v par=$avg_sparse_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
            dense_speedup=$(awk -v ser=$avg_dense_ser -v par=$avg_dense_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
            
            printf "FINAL AVG size=%s sparsity=%s%% iterations=%s processes=%s over %d runs:\n" "$size" "$spar" "$iter" "$proc" "$cnt" | tee -a "$OUTTXT"
            printf "  Sparse: parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_sparse_par" "$avg_sparse_ser" "$sparse_speedup" "$avg_comm_sparse" | tee -a "$OUTTXT"
            printf "  Dense:  parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_dense_par" "$avg_dense_ser" "$dense_speedup" "$avg_comm_dense" | tee -a "$OUTTXT"
          fi
        fi
      done
    done
  done
done

echo "" >> "$OUTTXT"
echo "======================================" >> "$OUTTXT"
echo "AGGREGATE STATISTICS BY PARAMETER:" >> "$OUTTXT"
echo "======================================" >> "$OUTTXT"

# By Sparsity
echo "" >> "$OUTTXT"
echo "BY SPARSITY:" >> "$OUTTXT"
for spar in "${SPARSITY[@]}"; do
  vals=$(awk -F, -v sp=$spar '$2==sp {print $7","$8","$9","$10","$11","$12}' "$OUTCSV")
  if [ -n "$vals" ]; then
    sum_sparse_par=0
    sum_sparse_ser=0
    sum_dense_par=0
    sum_dense_ser=0
    sum_comm_sparse=0
    sum_comm_dense=0
    cnt=0
    while IFS=, read -r sp_par sp_ser d_par d_ser c_sp c_d; do
      sum_sparse_par=$(awk -v a=$sum_sparse_par -v b=$sp_par 'BEGIN{printf "%.10f", a + b}')
      sum_sparse_ser=$(awk -v a=$sum_sparse_ser -v b=$sp_ser 'BEGIN{printf "%.10f", a + b}')
      sum_dense_par=$(awk -v a=$sum_dense_par -v b=$d_par 'BEGIN{printf "%.10f", a + b}')
      sum_dense_ser=$(awk -v a=$sum_dense_ser -v b=$d_ser 'BEGIN{printf "%.10f", a + b}')
      sum_comm_sparse=$(awk -v a=$sum_comm_sparse -v b=$c_sp 'BEGIN{printf "%.10f", a + b}')
      sum_comm_dense=$(awk -v a=$sum_comm_dense -v b=$c_d 'BEGIN{printf "%.10f", a + b}')
      cnt=$((cnt+1))
    done <<< "$vals"
    if [ $cnt -gt 0 ]; then
      avg_sparse_par=$(awk -v a=$sum_sparse_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_sparse_ser=$(awk -v a=$sum_sparse_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_par=$(awk -v a=$sum_dense_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_ser=$(awk -v a=$sum_dense_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_sparse=$(awk -v a=$sum_comm_sparse -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_dense=$(awk -v a=$sum_comm_dense -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      
      sparse_speedup=$(awk -v ser=$avg_sparse_ser -v par=$avg_sparse_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      dense_speedup=$(awk -v ser=$avg_dense_ser -v par=$avg_dense_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      
      printf "  Sparsity %s%% (over %d runs):\n" "$spar" "$cnt" | tee -a "$OUTTXT"
      printf "    Sparse: parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_sparse_par" "$avg_sparse_ser" "$sparse_speedup" "$avg_comm_sparse" | tee -a "$OUTTXT"
      printf "    Dense:  parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_dense_par" "$avg_dense_ser" "$dense_speedup" "$avg_comm_dense" | tee -a "$OUTTXT"
    fi
  fi
done

# By Size
echo "" >> "$OUTTXT"
echo "BY MATRIX SIZE:" >> "$OUTTXT"
for size in "${SIZES[@]}"; do
  vals=$(awk -F, -v s=$size '$1==s {print $7","$8","$9","$10","$11","$12}' "$OUTCSV")
  if [ -n "$vals" ]; then
    sum_sparse_par=0
    sum_sparse_ser=0
    sum_dense_par=0
    sum_dense_ser=0
    sum_comm_sparse=0
    sum_comm_dense=0
    cnt=0
    while IFS=, read -r sp_par sp_ser d_par d_ser c_sp c_d; do
      sum_sparse_par=$(awk -v a=$sum_sparse_par -v b=$sp_par 'BEGIN{printf "%.10f", a + b}')
      sum_sparse_ser=$(awk -v a=$sum_sparse_ser -v b=$sp_ser 'BEGIN{printf "%.10f", a + b}')
      sum_dense_par=$(awk -v a=$sum_dense_par -v b=$d_par 'BEGIN{printf "%.10f", a + b}')
      sum_dense_ser=$(awk -v a=$sum_dense_ser -v b=$d_ser 'BEGIN{printf "%.10f", a + b}')
      sum_comm_sparse=$(awk -v a=$sum_comm_sparse -v b=$c_sp 'BEGIN{printf "%.10f", a + b}')
      sum_comm_dense=$(awk -v a=$sum_comm_dense -v b=$c_d 'BEGIN{printf "%.10f", a + b}')
      cnt=$((cnt+1))
    done <<< "$vals"
    if [ $cnt -gt 0 ]; then
      avg_sparse_par=$(awk -v a=$sum_sparse_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_sparse_ser=$(awk -v a=$sum_sparse_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_par=$(awk -v a=$sum_dense_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_ser=$(awk -v a=$sum_dense_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_sparse=$(awk -v a=$sum_comm_sparse -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_dense=$(awk -v a=$sum_comm_dense -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      
      sparse_speedup=$(awk -v ser=$avg_sparse_ser -v par=$avg_sparse_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      dense_speedup=$(awk -v ser=$avg_dense_ser -v par=$avg_dense_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      
      printf "  Size %s (over %d runs):\n" "$size" "$cnt" | tee -a "$OUTTXT"
      printf "    Sparse: parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_sparse_par" "$avg_sparse_ser" "$sparse_speedup" "$avg_comm_sparse" | tee -a "$OUTTXT"
      printf "    Dense:  parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_dense_par" "$avg_dense_ser" "$dense_speedup" "$avg_comm_dense" | tee -a "$OUTTXT"
    fi
  fi
done

# By Iterations
echo "" >> "$OUTTXT"
echo "BY ITERATIONS:" >> "$OUTTXT"
for iter in "${ITERATIONS[@]}"; do
  vals=$(awk -F, -v it=$iter '$3==it {print $7","$8","$9","$10","$11","$12}' "$OUTCSV")
  if [ -n "$vals" ]; then
    sum_sparse_par=0
    sum_sparse_ser=0
    sum_dense_par=0
    sum_dense_ser=0
    sum_comm_sparse=0
    sum_comm_dense=0
    cnt=0
    while IFS=, read -r sp_par sp_ser d_par d_ser c_sp c_d; do
      sum_sparse_par=$(awk -v a=$sum_sparse_par -v b=$sp_par 'BEGIN{printf "%.10f", a + b}')
      sum_sparse_ser=$(awk -v a=$sum_sparse_ser -v b=$sp_ser 'BEGIN{printf "%.10f", a + b}')
      sum_dense_par=$(awk -v a=$sum_dense_par -v b=$d_par 'BEGIN{printf "%.10f", a + b}')
      sum_dense_ser=$(awk -v a=$sum_dense_ser -v b=$d_ser 'BEGIN{printf "%.10f", a + b}')
      sum_comm_sparse=$(awk -v a=$sum_comm_sparse -v b=$c_sp 'BEGIN{printf "%.10f", a + b}')
      sum_comm_dense=$(awk -v a=$sum_comm_dense -v b=$c_d 'BEGIN{printf "%.10f", a + b}')
      cnt=$((cnt+1))
    done <<< "$vals"
    if [ $cnt -gt 0 ]; then
      avg_sparse_par=$(awk -v a=$sum_sparse_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_sparse_ser=$(awk -v a=$sum_sparse_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_par=$(awk -v a=$sum_dense_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_ser=$(awk -v a=$sum_dense_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_sparse=$(awk -v a=$sum_comm_sparse -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_dense=$(awk -v a=$sum_comm_dense -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      
      sparse_speedup=$(awk -v ser=$avg_sparse_ser -v par=$avg_sparse_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      dense_speedup=$(awk -v ser=$avg_dense_ser -v par=$avg_dense_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      
      printf "  Iterations %s (over %d runs):\n" "$iter" "$cnt" | tee -a "$OUTTXT"
      printf "    Sparse: parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_sparse_par" "$avg_sparse_ser" "$sparse_speedup" "$avg_comm_sparse" | tee -a "$OUTTXT"
      printf "    Dense:  parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_dense_par" "$avg_dense_ser" "$dense_speedup" "$avg_comm_dense" | tee -a "$OUTTXT"
    fi
  fi
done

# By Processes
echo "" >> "$OUTTXT"
echo "BY PROCESSES:" >> "$OUTTXT"
for proc in "${PROCESSES[@]}"; do
  vals=$(awk -F, -v p=$proc '$4==p {print $7","$8","$9","$10","$11","$12}' "$OUTCSV")
  if [ -n "$vals" ]; then
    sum_sparse_par=0
    sum_sparse_ser=0
    sum_dense_par=0
    sum_dense_ser=0
    sum_comm_sparse=0
    sum_comm_dense=0
    cnt=0
    while IFS=, read -r sp_par sp_ser d_par d_ser c_sp c_d; do
      sum_sparse_par=$(awk -v a=$sum_sparse_par -v b=$sp_par 'BEGIN{printf "%.10f", a + b}')
      sum_sparse_ser=$(awk -v a=$sum_sparse_ser -v b=$sp_ser 'BEGIN{printf "%.10f", a + b}')
      sum_dense_par=$(awk -v a=$sum_dense_par -v b=$d_par 'BEGIN{printf "%.10f", a + b}')
      sum_dense_ser=$(awk -v a=$sum_dense_ser -v b=$d_ser 'BEGIN{printf "%.10f", a + b}')
      sum_comm_sparse=$(awk -v a=$sum_comm_sparse -v b=$c_sp 'BEGIN{printf "%.10f", a + b}')
      sum_comm_dense=$(awk -v a=$sum_comm_dense -v b=$c_d 'BEGIN{printf "%.10f", a + b}')
      cnt=$((cnt+1))
    done <<< "$vals"
    if [ $cnt -gt 0 ]; then
      avg_sparse_par=$(awk -v a=$sum_sparse_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_sparse_ser=$(awk -v a=$sum_sparse_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_par=$(awk -v a=$sum_dense_par -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_dense_ser=$(awk -v a=$sum_dense_ser -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_sparse=$(awk -v a=$sum_comm_sparse -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      avg_comm_dense=$(awk -v a=$sum_comm_dense -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
      
      sparse_speedup=$(awk -v ser=$avg_sparse_ser -v par=$avg_sparse_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      dense_speedup=$(awk -v ser=$avg_dense_ser -v par=$avg_dense_par 'BEGIN{if(par==0) print "0.00"; else printf "%.2f", ser/par}')
      
      printf "  Processes %s (over %d runs):\n" "$proc" "$cnt" | tee -a "$OUTTXT"
      printf "    Sparse: parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_sparse_par" "$avg_sparse_ser" "$sparse_speedup" "$avg_comm_sparse" | tee -a "$OUTTXT"
      printf "    Dense:  parallel=%s s, serial=%s s (speedup: %sx, comm: %s s)\n" "$avg_dense_par" "$avg_dense_ser" "$dense_speedup" "$avg_comm_dense" | tee -a "$OUTTXT"
    fi
  fi
done

echo "Done. CSV -> $OUTCSV, report -> $OUTTXT"
