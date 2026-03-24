#!/bin/bash
set -euo pipefail

# Benchmark script for 3_1 (MPI polynomial multiplication)

OUTDIR_CSV="results/csv"
OUTDIR_TXT="results/txt"
OUTCSV="$OUTDIR_CSV/results_3_1.csv"
OUTTXT="$OUTDIR_TXT/results_3_1.txt"
DEGREES_STR="10 10000 100000"
PROCS_STR="2 4"
REPEATS=4

read -r -a DEGREES <<< "$DEGREES_STR"
read -r -a PROCS <<< "$PROCS_STR"

# Create output directories
mkdir -p "$OUTDIR_CSV" "$OUTDIR_TXT"

# Initialize files
echo "degree,procs,run,serial_s,scattering_s,parallel_s,gathering_s,total_s,match" > "$OUTCSV"
echo "3_1 Benchmark Run (MPI Polynomial Multiplication)" > "$OUTTXT"
echo "$(date)" >> "$OUTTXT"
echo "" >> "$OUTTXT"

echo "Building 3_1..."
make 3_1 >/dev/null

for deg in "${DEGREES[@]}"; do
  for np in "${PROCS[@]}"; do
    for run in $(seq 1 $REPEATS); do
      printf "Running degree=%s procs=%s run=%s\n" "$deg" "$np" "$run"
      out=$(mpiexec -n "$np" ./3_1 "$deg" 2>&1 || true)

      serial=$(printf "%s" "$out" | grep -i "serial multiplication time" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
      scattering=$(printf "%s" "$out" | grep -i "data send time" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
      parallel=$(printf "%s" "$out" | grep -i "parallel multiplication time" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
      gathering=$(printf "%s" "$out" | grep -i "data gathering time" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
      total=$(printf "%s" "$out" | grep -i "total time including" | head -n1 | awk -F":" '{print $2}' | awk '{print $1}')
      match=$(printf "%s" "$out" | grep -i "Results match" >/dev/null && echo yes || echo no)

      serial=${serial:-0}
      scattering=${scattering:-0}
      parallel=${parallel:-0}
      gathering=${gathering:-0}
      total=${total:-0}

      # Append CSV
      echo "$deg,$np,$run,$serial,$scattering,$parallel,$gathering,$total,$match" >> "$OUTCSV"

      # Append human readable line
      printf "degree=%s procs=%s run=%s: serial=%s s parallel=%s s total=%s s match=%s\n" \
        "$deg" "$np" "$run" "$serial" "$parallel" "$total" "$match" >> "$OUTTXT"

      # Compute number of runs so far for this (deg,np)
      runs_so_far=$(awk -F, -v d=$deg -v p=$np '$1==d && $2==p {count++} END{print count+0}' "$OUTCSV")

      # Every 4 runs print average
      if [ $(( runs_so_far % 4 )) -eq 0 ]; then
        vals=$(awk -F, -v d=$deg -v p=$np '$1==d && $2==p {print $4","$5","$6","$7","$8}' "$OUTCSV" | tail -n 4)
        if [ -n "$vals" ]; then
          sum_serial=0
          sum_scattering=0
          sum_parallel=0
          sum_gathering=0
          sum_total=0
          cnt=0
          while IFS=, read -r s sc p g t; do
            sum_serial=$(awk -v a=$sum_serial -v b=$s 'BEGIN{printf "%.10f", a + b}')
            sum_scattering=$(awk -v a=$sum_scattering -v b=$sc 'BEGIN{printf "%.10f", a + b}')
            sum_parallel=$(awk -v a=$sum_parallel -v b=$p 'BEGIN{printf "%.10f", a + b}')
            sum_gathering=$(awk -v a=$sum_gathering -v b=$g 'BEGIN{printf "%.10f", a + b}')
            sum_total=$(awk -v a=$sum_total -v b=$t 'BEGIN{printf "%.10f", a + b}')
            cnt=$((cnt+1))
          done <<< "$vals"
          avg_serial=$(awk -v a=$sum_serial -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
          avg_scattering=$(awk -v a=$sum_scattering -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
          avg_parallel=$(awk -v a=$sum_parallel -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
          avg_gathering=$(awk -v a=$sum_gathering -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
          avg_total=$(awk -v a=$sum_total -v n=$cnt 'BEGIN{if(n==0)print 0; else printf "%.6f", a/n}')
          
          # Determine which is faster
          faster=""
          pct="0.00"
          faster_label=$(awk -v s=$avg_serial -v p=$avg_parallel 'BEGIN{ if(s>p) {f="parallel"; faster=p; slower=s} else if(p>s) {f="serial"; faster=s; slower=p} else {f="equal"; faster=0; slower=1} if(f=="equal") printf "%s", f; else printf "%s %.10f %.10f", f, faster, slower }')
          if [ "$faster_label" != "equal" ]; then
            read -r flabel fval sval <<< "$faster_label"
            pct=$(awk -v f=$fval -v s=$sval 'BEGIN{ if(s==0) print "0.00"; else printf "%.2f", (s - f)/s * 100 }')
            printf "AVERAGE (last %d) degree=%s procs=%s: avg_serial=%s s avg_parallel=%s s (total=%s s)\n" "$cnt" "$deg" "$np" "$avg_serial" "$avg_parallel" "$avg_total" | tee -a "$OUTTXT"
            printf "%s is faster by %s%%\n" "$flabel" "$pct" | tee -a "$OUTTXT"
          else
            printf "AVERAGE (last %d) degree=%s procs=%s: avg_serial=%s s avg_parallel=%s s (total=%s s)\n" "$cnt" "$deg" "$np" "$avg_serial" "$avg_parallel" "$avg_total" | tee -a "$OUTTXT"
            printf "comparison: equal\n" | tee -a "$OUTTXT"
          fi
        fi
      fi

    done
    echo "" >> "$OUTTXT"
  done
done

# Final averages
echo "" >> "$OUTTXT"
echo "FINAL AVERAGES:" >> "$OUTTXT"
for deg in "${DEGREES[@]}"; do
  for np in "${PROCS[@]}"; do
    vals=$(awk -F, -v d=$deg -v p=$np '$1==d && $2==p {print $4","$5","$6","$7","$8}' "$OUTCSV")
    if [ -n "$vals" ]; then
      sum_serial=0
      sum_scattering=0
      sum_parallel=0
      sum_gathering=0
      sum_total=0
      cnt=0
      while IFS=, read -r s sc p g t; do
        sum_serial=$(awk -v a=$sum_serial -v b=$s 'BEGIN{printf "%.10f", a + b}')
        sum_scattering=$(awk -v a=$sum_scattering -v b=$sc 'BEGIN{printf "%.10f", a + b}')
        sum_parallel=$(awk -v a=$sum_parallel -v b=$p 'BEGIN{printf "%.10f", a + b}')
        sum_gathering=$(awk -v a=$sum_gathering -v b=$g 'BEGIN{printf "%.10f", a + b}')
        sum_total=$(awk -v a=$sum_total -v b=$t 'BEGIN{printf "%.10f", a + b}')
        cnt=$((cnt+1))
      done <<< "$vals"
      if [ $cnt -gt 0 ]; then
        avg_serial=$(awk -v a=$sum_serial -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
        avg_scattering=$(awk -v a=$sum_scattering -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
        avg_parallel=$(awk -v a=$sum_parallel -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
        avg_gathering=$(awk -v a=$sum_gathering -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
        avg_total=$(awk -v a=$sum_total -v n=$cnt 'BEGIN{printf "%.6f", a/n}')
        
        # Determine which approach is faster and by what percentage for final averages
        faster_label=$(awk -v s=$avg_serial -v p=$avg_parallel 'BEGIN{ if(s>p) {f="parallel"; faster=p; slower=s} else if(p>s) {f="serial"; faster=s; slower=p} else {f="equal"; faster=0; slower=1} if(f=="equal") printf "%s", f; else printf "%s %.10f %.10f", f, faster, slower }')
        if [ "$faster_label" != "equal" ]; then
          read -r flabel fval sval <<< "$faster_label"
          pct=$(awk -v f=$fval -v s=$sval 'BEGIN{ if(s==0) print "0.00"; else printf "%.2f", (s - f)/s * 100 }')
          printf "FINAL AVG degree=%s procs=%s over %d runs:\n" "$deg" "$np" "$cnt" | tee -a "$OUTTXT"
          printf "  avg_serial=%s s\n" "$avg_serial" | tee -a "$OUTTXT"
          printf "  avg_parallel_comp=%s s\n" "$avg_parallel" | tee -a "$OUTTXT"
          printf "  avg_scattering=%s s avg_gathering=%s s avg_total_parallel=%s s\n" "$avg_scattering" "$avg_gathering" "$avg_total" | tee -a "$OUTTXT"
          printf "%s is faster by %s%%\n" "$flabel" "$pct" | tee -a "$OUTTXT"
        else
          printf "FINAL AVG degree=%s procs=%s over %d runs:\n" "$deg" "$np" "$cnt" | tee -a "$OUTTXT"
          printf "  avg_serial=%s s\n" "$avg_serial" | tee -a "$OUTTXT"
          printf "  avg_parallel_comp=%s s\n" "$avg_parallel" | tee -a "$OUTTXT"
          printf "  avg_scattering=%s s avg_gathering=%s s avg_total_parallel=%s s\n" "$avg_scattering" "$avg_gathering" "$avg_total" | tee -a "$OUTTXT"
          printf "comparison: equal\n" | tee -a "$OUTTXT"
        fi
      fi
    fi
  done
done

echo "Done. CSV -> $OUTCSV, report -> $OUTTXT"
