#!/bin/bash

# Changing this will require some changes in nekIBM-ascent
INSTALL_DIR=~/ascent-bidirectional
JUPYTER_SUPPORT=false

# Create install directory
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Clone nekIBM-ascent
git clone https://github.com/siramok/nekIBM-ascent.git

# Create sourceme file
if [ "$JUPYTER_SUPPORT" = true ] ; then
cat << EOF > sourceme
#!/bin/bash

# Load modules
module reset
module load cmake
module swap PrgEnv-nvhpc PrgEnv-gnu
module swap gcc/12.2.0 gcc/11.2.0
module load cudatoolkit-standalone

# Check for LD_PRELOAD
if [[ -z "\${LD_PRELOAD}" ]]; then
    export LD_PRELOAD=/opt/cray/pe/gcc/11.2.0/snos/lib64/libstdc++.so.6
fi

# Check for PYTHONPATH
if [[ -z "\${PYTHONPATH}" ]]; then
    export PYTHONPATH=$INSTALL_DIR/python-venv/lib/python3.6/site-packages:$INSTALL_DIR/ascent/scripts/build_ascent/install/ascent-develop/python-modules:$INSTALL_DIR/ascent/scripts/build_ascent/install/conduit-v0.8.8/python-modules
fi

# Check for NEK5000_HOME
if [[ -z "\${NEK5000_HOME}" ]]; then
    export NEK5000_HOME=$INSTALL_DIR/nekIBM-ascent
    export PATH=$INSTALL_DIR/nekIBM-ascent/bin:\$PATH
fi

# Source the Python venv
source $INSTALL_DIR/python-venv/bin/activate

EOF

# Setup Python venv
python3 -m venv python-venv
source sourceme
pip install --upgrade pip setuptools wheel numpy mpi4py jupyterlab


else
cat << EOF > sourceme
#!/bin/bash

# Load modules
module reset
module load cmake
module swap PrgEnv-nvhpc PrgEnv-gnu
module swap gcc/12.2.0 gcc/11.2.0
module load cudatoolkit-standalone

# Check for LD_PRELOAD
if [[ -z "\${LD_PRELOAD}" ]]; then
    export LD_PRELOAD=/opt/cray/pe/gcc/11.2.0/snos/lib64/libstdc++.so.6
fi

# Check for NEK5000_HOME
if [[ -z "\${NEK5000_HOME}" ]]; then
    export NEK5000_HOME=$INSTALL_DIR/nekIBM-ascent
    export PATH=$INSTALL_DIR/nekIBM-ascent/bin:\$PATH
fi

EOF

source sourceme
fi

# Clone Ascent repo
git clone https://github.com/siramok/ascent.git
cd ascent/scripts/build_ascent/

# Modify build script
rm build_ascent_cuda_polaris.sh

if [ "$JUPYTER_SUPPORT" = true ] ; then
cat << EOF > build_ascent_cuda_polaris.sh
#!/bin/bash

source $INSTALL_DIR/sourceme

export CC=$(which cc)
export CXX=$(which CC)

env build_jobs=8 enable_tests=OFF enable_mpi=ON enable_python=ON raja_enable_vectorization=OFF ./build_ascent_cuda.sh
EOF
else
cat << EOF > build_ascent_cuda_polaris.sh
#!/bin/bash

source $INSTALL_DIR/sourceme

export CC=$(which cc)
export CXX=$(which CC)

env build_jobs=8 enable_tests=OFF enable_mpi=ON raja_enable_vectorization=OFF ./build_ascent_cuda.sh
EOF
fi

# Make the new build script executable
chmod +x build_ascent_cuda_polaris.sh

# Build Ascent
./build_ascent_cuda_polaris.sh

if [ "$JUPYTER_SUPPORT" = true ] ; then
# Build ascent-jupyter-bridge
cd ascent/src/libs/ascent/python/ascent_jupyter_bridge/
pip install -r requirements.txt
sed -i 's/"enum34", //' setup.py
pip install .
fi

# Build nekIBM tools
cd $INSTALL_DIR/nekIBM-ascent/tools
./maketools all

# Setup lidar case
cd $INSTALL_DIR
cp -r /lus/eagle/clone/g2/projects/insitu/lidar_clean lidar
cd lidar
makenek uniform
