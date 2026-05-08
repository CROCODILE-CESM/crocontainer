
# FIre and forget 
podman run --rm \
  -v ~/my_data:/workspace/inputdata \
  -v ~/my_cases:/workspace/cases \
  crotainer

# Debugging
podman run --rm -it \
  -v /home/manishrv/crocontainer/panama-crocontainer_case_bundle:/workspace/bundle \
  localhost/crocontainer bash

# Bundle Command
crocodash read --caseroot /home/manishrv/croc_cases/panama-crocontainer --output-dir /home/manishrv/crocontainer --cesmroot /home/manishrv/CROCESM --machine ubuntu-latest --project PROJ123