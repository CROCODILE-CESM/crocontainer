import os
from CrocoDash.shareable.fork import ForkCrocoDashBundle

#Hard Coded Paths
bundle_location = "/workspace/bundle"
new_case_location = "/workspace/case"
new_input_location = "/workspace/inputdir"

def main():
    forker = ForkCrocoDashBundle(
        bundle_location=bundle_location,
        cesmroot = os.environ["CESMROOT"],
        machine="ubuntu-latest",
        project_number="PROJ123",
        new_caseroot=new_case_location,
        new_inputdir=new_input_location
        )
    os.environ["USER"] = "root"
    case = forker.fork(
    plan={"xml_files": True, "user_nl": True, "source_mods": True, "xmlchanges": True},
    compset = forker.manifest["init_args"]["compset"],
    extra_configs=[],                   # additional forcing configs to add
    remove_configs=[],                    # forcing configs to drop
    )

if __name__ == "__main__":
    main()