const responseCodes = {
  /* Status Code Format: XYZ 
   * X : 0 if success type, 1 if error type
   * Y : 0-n based on group of response (ie REGISTRATION is 1, AUTH is 2, and so on)
   * Z : 0-n increments as type changes within a group of response
   * 
   * For example:
   * 123 :
   * 1 = Error type of code
   * 2 = Authentication group
   * 3 = 3rd type of error within authentication group 
   */

  GENERIC_SUCCESS: 0,
  GENERIC_ERROR: 100,

  GET_DEVICE_INFO_SUCCESS: 40,
  GET_DEVICE_INFO_ERROR: 140,

  DEVICE_HOST_CONFIG_REFRESH_SUCCESS: 41,
  DEVICE_HOST_CONFIG_REFRESH_ERROR: 141,

  GET_SERVERS_LIST_SUCCESS: 50,
  GET_SERVERS_LIST_ERROR: 150,

  ADD_SERVER_SUCCESS: 60,
  ADD_SERVER_ERROR: 160,
  ADD_SERVER_DEVICE_NOT_YET_LINKED: 161,
  ADD_SERVER_DUPLICATE: 162,
  REMOVE_SERVER_SUCCESS: 63,
  REMOVE_SERVER_ERROR: 163,
  REMOVE_SERVER_NOT_FOUND: 164,

  DEVICE_LINKING_SUCCESS: 70,
  DEVICE_LINKING_ERROR: 170,
  DEVICE_LINKING_EHUB_ERROR: 171,
  DEVICE_LINKING_INVALID_USERNAME: 172,
  DEVICE_LINKING_INVALID_PASSWORD: 173,
  DEVICE_LINKING_INVALID_LONGITUDE_VALUE: 174,
  DEVICE_LINKING_INVALID_LATITUDE_VALUE: 175,
  DEVICE_LINKING_INVALID_ELEVATION_VALUE: 176,

  START_STREAMING_SUCCESS: 80,
  START_STREAMING_ERROR: 180,
  START_STREAMING_INVALID_URL: 181,
  START_STREAMING_DUPLICATE: 182,

  GET_STREAMS_STATUS_SUCCESS: 90,
  GET_STREAMS_STATUS_ERROR: 190,

  HEALTH_NETWORK_SUCCESS: 95,
  HEALTH_NETWORK_ERROR: 195,
  HEALTH_TIME_SUCCESS: 96,
  HEALTH_TIME_ERROR: 196,
  HEALTH_RESOURCES_SUCCESS: 98,
  HEALTH_RESOURCES_ERROR: 198,
  DEVICE_TOKEN_REFRESH_SUCCESS: 97,
  DEVICE_TOKEN_REFRESH_ERROR: 197,
  DEVICE_RELINK_REQUIRED: 199,

  STOP_STREAMING_SUCCESS: 30,
  STOP_STREAMING_ERROR: 130,

  DEVICE_UNLINKING_SUCCESS: 20,
  DEVICE_UNLINKING_ERROR: 120,
  DEVICE_UNLINKING_EHUB_ERROR: 121,
  DEVICE_RESET_SUCCESS: 21,
  DEVICE_RESET_ERROR: 122,
  DEVICE_RESET_EHUB_ERROR: 123,
};

const responseMessages = {
  GENERIC_SUCCESS: "Success",
  GENERIC_ERROR: "Error",

  GET_DEVICE_INFO_SUCCESS: "Reading device information success",
  GET_DEVICE_INFO_ERROR: "Reading device information error",
  DEVICE_HOST_CONFIG_REFRESH_SUCCESS: "Device metadata refresh success",
  DEVICE_HOST_CONFIG_REFRESH_ERROR: "Device metadata refresh error",

  GET_SERVERS_LIST_SUCCESS: "Reading servers list information success",
  GET_SERVERS_LIST_ERROR: "Reading servers list information error",

  ADD_SERVER_SUCCESS: "Add server success",
  ADD_SERVER_ERROR: "Add server error",
  ADD_SERVER_DEVICE_NOT_YET_LINKED: "Device is not yet linked. Link first.",
  ADD_SERVER_INVALID_HOSTNAME: "Invalid input hostname",
  ADD_SERVER_DUPLICATE: "Server URL already saved",
  REMOVE_SERVER_SUCCESS: "Remove server success",
  REMOVE_SERVER_ERROR: "Remove server error",
  REMOVE_SERVER_NOT_FOUND: "Server URL not found",

  DEVICE_LINKING_SUCCESS: "Device linking success",
  DEVICE_LINKING_ERROR: "Device linking error",
  DEVICE_LINKING_EHUB_ERROR: "Error from earthquakehub", 

  START_STREAMING_SUCCESS: "Spawning child process success",
  START_STREAMING_ERROR: "Spawning child process error",
  START_STREAMING_INVALID_URL: "Invalid URL",
  START_STREAMING_DUPLICATE: "Device is already streaming to the specified URL",

  GET_STREAMS_STATUS_SUCCESS: "Get streams status success",
  GET_STREAMS_STATUS_ERROR: "Get streams status error",

  HEALTH_NETWORK_SUCCESS: "Network health check success",
  HEALTH_NETWORK_ERROR: "Network health check error",
  HEALTH_TIME_SUCCESS: "Time health check success",
  HEALTH_TIME_ERROR: "Time health check error",
  HEALTH_RESOURCES_SUCCESS: "Resource utilization snapshot success",
  HEALTH_RESOURCES_ERROR: "Resource utilization snapshot error",
  DEVICE_TOKEN_REFRESH_SUCCESS: "Access token refresh success",
  DEVICE_TOKEN_REFRESH_ERROR: "Access token refresh error",
  DEVICE_RELINK_REQUIRED: "Device credentials invalid. Relink required",
  DEVICE_RESET_SUCCESS: "Device reset success",
  DEVICE_RESET_ERROR: "Device reset error",
  DEVICE_RESET_EHUB_ERROR: "Device reset error from earthquakehub",
};

module.exports = {
  responseCodes,
  responseMessages,
};
