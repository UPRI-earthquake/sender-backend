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

  GET_SERVERS_LIST_SUCCESS: 50,
  GET_SERVERS_LIST_ERROR: 150,

  DEVICE_LINKING_SUCCESS: 60,
  DEVICE_LINKING_ERROR: 160,
  DEVICE_LINKING_INVALID_INPUT: 161,

  GET_STREAMS_STATUS_SUCCESS: 70,
  GET_STREAMS_STATUS_ERROR: 170,

  AUTHENTICATION_SUCCESS: 20,
  AUTHENTICATION_TOKEN_COOKIE: 21,
  AUTHENTICATION_TOKEN_PAYLOAD: 22,
  AUTHENTICATION_ERROR: 120,
  AUTHENTICATION_USER_NOT_EXIST: 121,
  AUTHENTICATION_INVALID_ROLE: 122,
  AUTHENTICATION_WRONG_PASSWORD: 123,
  AUTHENTICATION_NO_LINKED_DEVICE: 124,

  VERIFICATION_SUCCESS: 30,
  VERIFICATION_SUCCESS_NEW_TOKEN: 31,
  VERIFICATION_ERROR: 130,
  VERIFICATION_INVALID_TOKEN: 131,
  VERIFICATION_INVALID_ROLE: 132,
  VERIFICATION_EXPIRED_TOKEN: 133,
};

const responseMessages = {
  GENERIC_SUCCESS: "Success",
  GENERIC_ERROR: "Error",

  GET_STREAMS_STATUS_SUCCESS: "Get streams status success",
  GET_STREAMS_STATUS_ERROR: "Get streams status error",

  GET_DEVICE_INFO_SUCCESS: "Reading device information success",
  GET_DEVICE_INFO_ERROR: "Reading device information error",

  GET_SERVERS_LIST_SUCCESS: "Reading servers list information success",
  GET_SERVERS_LIST_ERROR: "Reading servers list information error",

  DEVICE_LINKING_SUCCESS: "Device linking success",
  DEVICE_LINKING_ERROR: "Device linking error",

  VERIFICATION_SUCCESS: "Verification success",
  VERIFICATION_SUCCESS_NEW_TOKEN: "Verification success with new token",
  VERIFICATION_ERROR: "Verification error",
  VERIFICATION_INVALID_TOKEN: "Verification error: Invalid token",
  VERIFICATION_INVALID_ROLE: "Verification error: Invalid role in token",
  VERIFICATION_EXPIRED_TOKEN: "Verification error: Expired token",
};

module.exports = {
  responseCodes,
  responseMessages,
};
