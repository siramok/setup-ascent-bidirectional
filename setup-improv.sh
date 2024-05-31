#!/bin/bash

# Load modules
module load gcc
module load openmpi
module load python/3.11.6-gcc-13.2.0
module load cmake

# Change install directory if desired
INSTALL_DIR=~/ascent-bidirectional

# Create install directory
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Create Python venv
python -m venv venv
source $INSTALL_DIR/venv/bin/activate
pip install --upgrade pip setuptools wheel numpy mpi4py jupyterlab notebook pyyaml open3d

# Clone custom Ascent
git clone https://github.com/siramok/ascent.git

# Clone nekIBM-ascent
git clone --branch improv https://github.com/siramok/nekIBM-ascent.git

# Clone simulation data
git clone https://github.com/siramok/nekIBM-lidar-sample.git $INSTALL_DIR/lidar

# Create interactive-job file
cat << EOF > interactive
# 1 node for debugging
qsub -I -A ascent-insitu -l select=1:ncpus=128:mpiprocs=128,walltime=01:00:00 -q debug

# 10 nodes for running cases
qsub -I -A ascent-insitu -l select=10:ncpus=128:mpiprocs=128,walltime=02:00:00 -q compute

EOF

# Create sourceme file
cat << EOF > sourceme
#!/bin/bash

# Load modules
module load gcc
module load openmpi
module load python/3.11.6-gcc-13.2.0
module load cmake

source $INSTALL_DIR/venv/bin/activate
export PYTHON_EXECUTABLE=$INSTALL_DIR/venv/bin/python

# Check for PYTHONPATH
if [[ -z "\${PYTHONPATH}" || "\${PYTHONPATH}" != *"ascent"* ]]; then
    export PYTHONPATH=$INSTALL_DIR/venv/lib/python3.11/site-packages:$INSTALL_DIR/ascent/scripts/build_ascent/install/ascent-develop/python-modules:$INSTALL_DIR/ascent/scripts/build_ascent/install/conduit-v0.9.1/python-modules
fi

# Check for NEK5000_HOME
if [[ -z "\${NEK5000_HOME}" ]]; then
    export NEK5000_HOME=$INSTALL_DIR/nekIBM-ascent
    export PATH=$INSTALL_DIR/nekIBM-ascent/bin:"\${PATH}"
fi
EOF

# Load necessary modules
source $INSTALL_DIR/sourceme

# Modify Ascent build script
cd $INSTALL_DIR/ascent/scripts/build_ascent/
cat << EOF > build_ascent_improv.sh
#!/bin/bash -l

source $INSTALL_DIR/sourceme

env enable_mpi=ON enable_python=ON enable_tests=OFF ./build_ascent.sh
EOF
chmod +x build_ascent_improv.sh

# Build Ascent
./build_ascent_improv.sh

# Fix paths
replace_line() {
    local file=$1
    local line_number=$2
    local new_line=$3
    local escaped_new_line=$(printf '%s\n' "$new_line" | sed 's/[&/\]/\\&/g')
    sed -i "${line_number}s/.*/${escaped_new_line}/" "$file"
}

ASCENT_CONFIG=$INSTALL_DIR/ascent/scripts/build_ascent/install/ascent-develop/share/ascent/ascent_config.mk

replace_line "$ASCENT_CONFIG" 90 "ASCENT_UMPIRE_RPATH_FLAGS_VALUE = -Wl,-rpath,\$(ASCENT_UMPIRE_DIR)/lib64"
replace_line "$ASCENT_CONFIG" 215 "ASCENT_UMPIRE_LIB_FLAGS = \$(if \$(ASCENT_UMPIRE_DIR),-L \$(ASCENT_UMPIRE_DIR)/lib64 -lumpire)"
replace_line "$ASCENT_CONFIG" 220 "ASCENT_CAMP_LIB_FLAGS = \$(if \$(ASCENT_CAMP_DIR),-L \$(ASCENT_CAMP_DIR)/lib -lcamp)"

# Build ascent_jupyter_bridge
cd $INSTALL_DIR/ascent/scripts/build_ascent/ascent/src/libs/ascent/python/ascent_jupyter_bridge/
pip install -r requirements.txt
pip install .

# Replace the install directory within nekIBM-ascent
if [ "$INSTALL_DIR" != "~/ascent-bidirectional" ]
then
    sed -i "s|~/ascent-bidirectional|${INSTALL_DIR}|g" $INSTALL_DIR/nekIBM-ascent/bin/makenek
    sed -i "s|~/ascent-bidirectional|${INSTALL_DIR}|g" $INSTALL_DIR/nekIBM-ascent/core/makefile.template
    sed -i "s|~/ascent-bidirectional|${INSTALL_DIR}|g" $INSTALL_DIR/nekIBM-ascent/tools/maketools
    sed -i "s|~/ascent-bidirectional|${INSTALL_DIR}|g" $INSTALL_DIR/nekIBM-ascent/3rd_party/nek_ascent/CMakeLists.txt
fi

# Build nekIBM-ascent tools
cd $INSTALL_DIR/nekIBM-ascent/tools
./maketools all

# Build lidar sample case
cd $INSTALL_DIR/lidar
makenek uniform

# End
echo "Finished building ascent-bidirectional"
