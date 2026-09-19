class ApiEndPoints {
//API End Points for Staff
  static const String getallStaff = "3406/staff/getall";
  static const String updateStaff = "3404/staff/update";
  static const String loginStaff = '1215/login';
  static const String getlowerStaff = "8845/belowstaffs/getall";

  // API Endpoints for OTP (email + SMS)
  static const String otpSend = "8016/otp/send";
  static const String otpVerify = "8016/otp/verify";

  //API Endpoints for Tasks
  static const String getallTasks = "3411/task/getall";
  static const String updateTasks = "3410/task/update";
  //version check
  static const String versionCheck = '1210/appversion/getall';

  //API Endpoints for Ratings
  static const String getRatings = "9545/productreviews/getall";

  // API Endpoint for image upload
  static const String imageupload = "9104/imageupload/create";

  // API Endpoint for customer (hotel details)
  static const String getAllCustomers = "9526/customer/getall";

  // API Endpoint for sending a test push (used to validate a device FCM token)
  // static const String orderNotification = "5621/api/payment/TaskNotification";
  static const String orderNotification = "5621/api/payment/OrderNotification";
}
