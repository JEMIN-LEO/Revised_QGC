# QGroundControl 4.3.0 定制修改说明

本文档记录当前源码相对于 QGroundControl 4.3.0 的定制修改，目标是让 PX4 通过低带宽 LR900 数传时优先完成 Mission，并减少连接阶段的链路占用。

## 1. 修改目标

- 初始连接时优先读取普通 Mission 航线。
- 跳过连接阶段的全量参数、组件信息、GeoFence 和 Rally 下载。
- 降低 Mission 传输因数传延迟产生误判失败的概率。
- Mission 读取失败后清理本地事务状态，等待后重新建立一次读取。
- 每次 PX4连接完成后自动关闭指定的高频/无用 MAVLink消息。
- 保留 Mission、心跳和飞行显示所需的核心遥测消息。

## 2. 初始连接流程

修改文件：

`src/Vehicle/InitialConnectStateMachine.cc`、`InitialConnectStateMachine.h`

原始连接流程中的以下步骤已移除：

- 组件信息请求；
- 全量参数请求；
- GeoFence下载；
- Rally点下载。

当前初始连接流程主要为：

```text
请求能力/协议/标准模式
        ->
读取普通 Mission
        ->
标记 initialPlanRequestComplete
        ->
发送 initialConnectComplete
```

这样做可以避免约千个参数报文和额外计划数据在 LR900链路上与 Mission竞争。

参数上传接口没有删除。用户显式进入参数功能或调用参数刷新时，仍可能触发参数请求。

## 3. GeoFence 和 Rally

修改文件：

`src/MissionManager/PlanMasterController.cc`

连接加载时：

```cpp
_loadGeoFence = false;
_loadRallyPoints = false;
```

因此初始连接只加载普通 Mission。GeoFence和 Rally仍由各自管理器保留，只有显式操作时才可能加载。

## 4. Mission超时与失败恢复

修改文件：

`src/MissionManager/PlanManager.cc`、`PlanManager.h`

超时参数调整为：

```cpp
_ackTimeoutMilliseconds   = 1500;
_retryTimeoutMilliseconds = 1500;
_maxRetryCount            = 10;
```

相比原来的 250 ms重试间隔和 5次重试，当前设置允许 LR900在存在排队延迟时有更长响应时间。

当 Mission读取事务最终失败时，新增一次自动恢复：

```text
结束当前读取事务
断开 Mission MAVLink监听
清理旧航点和请求状态
等待 1.5 秒
重新建立读取事务
重新发送 MISSION_REQUEST_LIST
```

每次用户主动发起读取最多自动恢复一次。恢复仍失败后才保持失败结果，避免无限重试或多个 Mission事务并发。

这属于 QGC软件状态机清理，不会给 LR900重新上电，也不会清空 LR900硬件缓存或重置 UART。

## 5. PX4消息限流

修改文件：

`src/FirmwarePlugin/PX4/PX4FirmwarePlugin.cc`

每次 PX4车辆初始连接完成后，QGC通过：

```text
MAV_CMD_SET_MESSAGE_INTERVAL (command=511)
param2 = -1
```

逐条请求 PX4停止发送指定消息。

命令采用 ACK串行队列：收到上一条 ACK后才发送下一条，避免 QGC将同一 `MAV_CMD` 判定为重复命令。连接完成信号存在时序差异时，也会通过立即检查和 Qt事件循环补偿，防止漏执行。

当前关闭的消息包括：

```text
RAW_IMU
SCALED_IMU
SCALED_IMU2
SCALED_IMU3
HIGHRES_IMU
ATTITUDE_QUATERNION
VIBRATION
DEBUG
DEBUG_VECT
DEBUG_FLOAT_ARRAY
NAMED_VALUE_FLOAT
NAMED_VALUE_INT
PID_TUNING
CONTROL_SYSTEM_STATE
ODOMETRY
AVAILABLE_MODES
CURRENT_MODE
MOUNT_ORIENTATION
SCALED_PRESSURE
TIME_ESTIMATE_TO_TARGET
OPEN_DRONE_ID_LOCATION
OPEN_DRONE_ID_SYSTEM
OPEN_DRONE_ID_ARM_STATUS
EFI_STATUS
ESC_INFO
ESC_STATUS
HYGROMETER_SENSOR
GPS_GLOBAL_ORIGIN
```

当前明确保留：

```text
ATTITUDE
GPS_RAW_INT
GLOBAL_POSITION_INT
RC_CHANNELS
VFR_HUD
```

此外，心跳、Mission协议、命令 ACK、必要状态文本等没有被该列表关闭。`FUEL_STATUS`不在本工程使用的 MAVLink common方言中，因此没有加入不存在的消息常量。

注意：该策略只在 QGC连接后通过 MAVLink下发，不是永久写入 PX4参数。飞控重启后需要再次连接 QGC才能重新应用。

## 6. 已知行为和限制

### Vehicle Setup可能为空

由于初始连接不再自动完成全量参数初始化，`ParameterManager::parametersReady()`可能不会达到完整状态。依赖完整参数的 Vehicle Setup、Actuator、校准等界面可能为空或缺少组件。

Mission下载、Mission上传、模式/位置/高度/空速等遥测不依赖完整参数下载，但参数相关界面或显式刷新仍可能请求参数。

### 第二次进度条

如果日志中出现 `PARAM_REQUEST_READ`或 `PARAM_VALUE`，说明仍有其他代码路径或界面主动读取参数。它不是当前 InitialConnectStateMachine中的自动全量参数步骤。

### 消息关闭命令的 ACK

部分 PX4版本或消息可能不支持 `MAV_CMD_SET_MESSAGE_INTERVAL`，对应 ACK可能不是 ACCEPTED。当前队列仍会继续发送后续消息，不应把单条不支持理解为 Mission失败。

### 硬件流控不在本修改范围

QGC消息限流不能改变 PX4 TELEM1 UART的 RTS/CTS硬件流控，也不能修复 LR900供电、天线、UART缓存、无线干扰或模块内部状态。当前系统已关闭硬件流控时，仍需独立验证串口和无线链路。

## 7. 验证方式

启动当前构建程序：

```bash
/home/jeminliu/qgroundcontrol/build/QGroundControl
```

连接 PX4后，终端应出现：

```text
Applied narrow-band telemetry message policy
```

对应 `.tlog`中应看到多条：

```text
COMMAND_LONG command=511 param2=-1
```

Mission成功的基本判据：

- `MISSION_COUNT`数量正确；
- 每个 `MISSION_ITEM_INT`均收到；
- 最终 `MISSION_ACK`为 `type=0`；
- 没有 `Operation timeout`；
- 没有 `WPM: REJ. CMD: Busy`；
- 没有持续的 `GCS connection lost`；
- 心跳间隔通常小于 2秒。

## 8. 编译

当前 Debug构建目录：

```bash
cd /home/jeminliu/qgroundcontrol
cmake --build build --parallel "$(nproc)"
```

成功产物：

```text
/home/jeminliu/qgroundcontrol/build/QGroundControl
```

编译时可能出现 `Mixer.h`中的未使用参数警告；该警告不是本次定制修改导致的编译错误。

