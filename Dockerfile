FROM ubuntu:20.04

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 lsb-release software-properties-common \
    build-essential git cmake \
    python3-pip \
    libceres-dev libeigen3-dev \
    libpcl-dev \
    nlohmann-json3-dev \
    tmux \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros1.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-desktop-full \
    python3-rosdep \
    python3-catkin-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone https://github.com/Livox-SDK/Livox-SDK.git && \
    cd Livox-SDK && \
    rm -rf build && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install

WORKDIR /ros_ws

COPY ./src ./src

RUN sed -i \
    -e 's|lid_topic:.*|lid_topic:  "/livox/lidar"|' \
    -e 's|imu_topic:.*|imu_topic:  "/livox/imu"|' \
    -e 's|lidar_type:.*|lidar_type: 1|' \
    src/c3p-voxelmap/config/velodyne.yaml

# Canonical-bag sensor profile (config + launch), kept out of the upstream
# c3p-voxelmap submodule: its own velodyne.yaml with only the sensor description
# changed.
COPY ./overlay/config/ ./src/c3p-voxelmap/config/
COPY ./overlay/launch/ ./src/c3p-voxelmap/launch/

# Canonical bag: the VELO32 handler (lidar_type 5) converts the per-point
# `time` field to milliseconds with time * 1e-3, i.e. it expects microseconds;
# the canonical bag's `time` is in seconds (as Velodyne drivers publish it), so
# deskew would see ~0 offsets. Use time * 1e3. Fails the build if the line
# changes.
RUN f=src/c3p-voxelmap/src/preprocess.cpp && \
    [ "$(grep -c 'added_pt.curvature = pl_orig.points\[i\].time \* 1e-3;' $f)" = 1 ] && \
    sed -i 's/added_pt.curvature = pl_orig.points\[i\].time \* 1e-3;/added_pt.curvature = pl_orig.points[i].time * 1e3;/' $f && \
    [ "$(grep -c 'added_pt.curvature = pl_orig.points\[i\].time \* 1e3;' $f)" = 1 ]

RUN source /opt/ros/noetic/setup.bash && \
        catkin_make --pkg livox_ros_driver

RUN source /opt/ros/noetic/setup.bash && \
    source /ros_ws/devel/setup.bash && \
    catkin_make

ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID ros && \
    useradd -m -u $UID -g $GID -s /bin/bash ros
WORKDIR /ros_ws

RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc && \
    echo "source /ros_ws/devel/setup.bash" >> ~/.bashrc

CMD ["bash"]