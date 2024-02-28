#!/bin/bash

# Change install directory if desired
INSTALL_DIR=~/ascent-bidirectional

# Create install directory
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Clone custom Ascent
git clone https://github.com/siramok/ascent.git

# Clone nekIBM-ascent
git clone https://github.com/siramok/nekIBM-ascent.git

# Clone simulation data
git clone https://github.com/siramok/nekIBM-lidar-sample.git $INSTALL_DIR/lidar

# Create sourceme file
cat << EOF > sourceme
#!/bin/bash

# Load modules
module reset
module load cmake
module swap PrgEnv-nvhpc PrgEnv-gnu
module swap gcc/12.2.0 gcc/11.2.0
module load cudatoolkit-standalone
module load cray-python

# Check for LD_PRELOAD
if [[ -z "\${LD_PRELOAD}" ]]; then
    export LD_PRELOAD=/opt/cray/pe/gcc/11.2.0/snos/lib64/libstdc++.so.6
fi

# Check for PYTHONPATH
if [[ -z "\${PYTHONPATH}" || "\${PYTHONPATH}" != *"ascent"* ]]; then
    export PYTHONPATH=$INSTALL_DIR/ascent/scripts/build_ascent/install/ascent-develop/python-modules:$INSTALL_DIR/ascent/scripts/build_ascent/install/conduit-v0.8.8/python-modules:"\${PYTHONPATH}"
fi

# Check for NEK5000_HOME
if [[ -z "\${NEK5000_HOME}" ]]; then
    export NEK5000_HOME=$INSTALL_DIR/nekIBM-ascent
    export PATH=$INSTALL_DIR/nekIBM-ascent/bin:"\${PATH}"
fi
EOF

# Load necessary modules
source $INSTALL_DIR/sourceme

# Install Python dependencies
pip install --upgrade pip setuptools wheel numpy mpi4py jupyterlab notebook pyyaml

# Modify Ascent build script
cd $INSTALL_DIR/ascent/scripts/build_ascent/
rm build_ascent_cuda_polaris.sh
cat << EOF > build_ascent_cuda_polaris.sh
#!/bin/bash

source $INSTALL_DIR/sourceme

export CC=\$(which cc)
export CXX=\$(which CC)

env build_jobs=8 enable_tests=OFF enable_mpi=ON enable_python=ON raja_enable_vectorization=OFF ./build_ascent.sh
EOF
chmod +x build_ascent_cuda_polaris.sh

# Build Ascent
./build_ascent_cuda_polaris.sh

# Build ascent_jupyter_bridge
cd $INSTALL_DIR/ascent/scripts/build_ascent/ascent/src/libs/ascent/python/ascent_jupyter_bridge/
sed -i 's/"enum34", //' setup.py
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
