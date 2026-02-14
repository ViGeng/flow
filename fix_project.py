import re

project_path = 'Flow.xcodeproj/project.pbxproj'

with open(project_path, 'r') as f:
    content = f.read()

# Generate IDs
file_ref_id = "FACADE01FACADE01FACADE01"
build_file_id = "FACADE02FACADE02FACADE02"

# 1. Add PBXBuildFile section if missing, or add to it
build_file_entry = f'\t\t{build_file_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* Assets.xcassets */; }};\n'

if '/* Begin PBXBuildFile section */' in content:
    content = content.replace('/* Begin PBXBuildFile section */', f'/* Begin PBXBuildFile section */\n{build_file_entry}')
else:
    # Insert before PBXFileReference section
    content = content.replace('/* Begin PBXFileReference section */', f'/* Begin PBXBuildFile section */\n{build_file_entry}/* End PBXBuildFile section */\n\n/* Begin PBXFileReference section */')

# 2. Add PBXFileReference
file_ref_entry = f'\t\t{file_ref_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};\n'
content = content.replace('/* Begin PBXFileReference section */', f'/* Begin PBXFileReference section */\n{file_ref_entry}')

# 3. Add to PBXResourcesBuildPhase
# Find the Resources build phase for the main target (Flow)
# We know the ID is B6D369282F3F3C400090CDB7 from reading the file
resources_build_phase_id = "B6D369282F3F3C400090CDB7"
pattern = re.compile(f'{resources_build_phase_id} /\* Resources \*/ = {{[^}}]*files = \(\n', re.MULTILINE | re.DOTALL)

def replace_files(match):
    return match.group(0) + f'\t\t\t\t{build_file_id} /* Assets.xcassets in Resources */,\n'

content = pattern.sub(replace_files, content)

# 4. Add to PBXGroup (Main Group) to make it visible?
# Actually, if it's in Flow folder, adding it to the project root might be weird if Flow is a group.
# But let's add it to the main group B6D369212F3F3C400090CDB7 just to be safe it's referenced.
# Wait, Flow/Assets.xcassets implies it's in Flow group.
# But Flow group B6D3692C... is a Sync Root.
# If I add it to the Main Group, I need to make sure path is correct relative to project.
# Main Group path is empty (project root).
# So path should be Flow/Assets.xcassets?
# The FileRef I added above says path = Assets.xcassets. This assumes it's in the same dir as project or in the group's path.
# If I put it in Main Group, path needs to be full relative path: "Flow/Assets.xcassets".
# Let's correct the FileRef path:
content = content.replace('path = Assets.xcassets;', 'path = Flow/Assets.xcassets;')

# Now add to Main Group children
main_group_id = "B6D369212F3F3C400090CDB7"
pattern_group = re.compile(f'{main_group_id} = {{[^}}]*children = \(\n', re.MULTILINE | re.DOTALL)

def replace_group(match):
    return match.group(0) + f'\t\t\t\t{file_ref_id} /* Assets.xcassets */,\n'

content = pattern_group.sub(replace_group, content)

with open(project_path, 'w') as f:
    f.write(content)
