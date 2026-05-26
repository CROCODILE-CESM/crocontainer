import os
from CrocoDash.shareable.fork import ForkCrocoDashBundle

# Hard Coded Paths
bundle_location = "/workspace/bundle"
new_case_location = "/workspace/case"
new_input_location = "/workspace/inputdir"


def main():
    os.environ["USER"] = "root"
    forker = ForkCrocoDashBundle(bundle_location)
    forker.fork(
        cesmroot=os.environ["CESMROOT"],
        machine="ubuntu-latest",
        project_number="PROJ123",
        new_caseroot=new_case_location,
        new_inputdir=new_input_location,
        plan={"xml_files": True, "user_nl": True, "source_mods": True, "xmlchanges": False},
        extra_configs=[],
        remove_configs=[],
    )


if __name__ == "__main__":
    main()