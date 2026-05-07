
# FIre and forget 
podman run --rm \
  -v ~/my_data:/workspace/inputdata \
  -v ~/my_cases:/workspace/cases \
  crotainer

# Debugging
podman run --rm -it \
  -v ~/my_data:/workspace/inputdata \
  -v ~/my_cases:/workspace/cases \
  crotainer bash