TARGET_DIR="/root/cesm/inputdata/ocn/jra55/v1.3_noleap"
mkdir -p "$TARGET_DIR"

# Your exact strings
VARS=("prec" "lwdn" "q_10" "swdn" "t_10" "u_10" "slp" "v_10")

for year in {1958..2024}; do
    # Skip 2020
    if [ "$year" -eq 2020 ]; then
        continue
    fi
    
    for var in "${VARS[@]}"; do
        # Creating files using your exact strings
        touch "$TARGET_DIR/JRA.v1.3.${var}.TL319.${year}.171019.nc"
    done
done

echo "Placeholder files created using your exact strings (excluding 2020)."
