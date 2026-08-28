@RestResource(urlMapping='/applicationUsersDetail/*')
/**
 * REST API for exposing single Application User detail to external consumers.
 * Based on CNBS API documentation: /cnbs/v1/apu/users/id
 */
global with sharing class ApplicationUserDetailAPI {

    @HttpGet
    global static void getApplicationUser() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            String userId = getUserIdFromRequest(req);
            if (String.isBlank(userId)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'user_id is required'))));
                return;
            }

            List<Chronarpay_User__c> users = [
                SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Company__c, Status__c, User_Role__c, 
                	   Invite_Token__c, Password_Reset_Token__c, Confirmation_Token__c, Number_of_Logins__c, Failed_Login_Count__c, 
                       CreatedDate, LastModifiedDate, Last_Login_Date__c, Last_Password_Change_Date__c, Salt__c, Hash__c, Primary_Account_Type__c
                FROM Chronarpay_User__c
                WHERE Id = :userId
                LIMIT 1
            ];

            if (users.isEmpty()) {
                res.statusCode = 404;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'User not found'))));
                return;
            }

            ApiResponse apiResponse = new ApiResponse(
                new List<UserResponse>{ buildUserResponse(users[0]) },
                buildStatusResponse('S', 'Request successfully processed ,document selected 1')
            );

            res.statusCode = 200;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(apiResponse));
        } catch (Exception e) {
            res.statusCode = 500;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', e.getMessage()))));
        }
    }

    @HttpPost
    global static void processRequest() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'Request body is required'))));
                return;
            }

            Map<String, Object> requestMap = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            String action = requestMap.containsKey('action') ? String.valueOf(requestMap.get('action')) : null;
            Map<String, Object> data = requestMap.containsKey('data') && requestMap.get('data') instanceof Map<String, Object>
                ? (Map<String, Object>) requestMap.get('data')
                : null;

            if (String.isBlank(action) || data == null) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'action and data are required'))));
                return;
            }

            action = action.toLowerCase();
            if (!action.equals('create') && !action.equals('modify') && !action.equals('delete')) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'Unsupported action'))));
                return;
            }

            String userId = getStringValue(data, 'user_id');
            String login = getStringValue(data, 'login');
            String firstName = getStringValue(data, 'first_name');
            String lastName = getStringValue(data, 'last_name');
            String company = getStringValue(data, 'company');
            String email = getStringValue(data, 'email');
            String status = getStringValue(data, 'status');
			String userRole = getStringValue(data, 'user_role');
            String userAccountType = getStringValue(data, 'primary_account_type_id');
            String salt = getStringValue(data, 'salt');
            String hash = getStringValue(data, 'hash');
            String invite_token = getStringValue(data, 'invite_token');
            String password_reset_token = getStringValue(data, 'password_reset_token');
            String confirmation_token = getStringValue(data, 'confirmation_token');

            if (action.equals('create')) {
                if (String.isBlank(login)) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'login is required on create'))));
                    return;
                }

                if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(email)) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'first_name, last_name and email are required on create'))));
                    return;
                }

                Chronarpay_User__c newUser = new Chronarpay_User__c();
                newUser.Name = login;
                newUser.First_Name__c = firstName;
                newUser.Last_Name__c = lastName;
                newUser.Email__c = email;
                newUser.Company__c = String.isBlank(company) ? 'CNBS' : company;
                newUser.Status__c = String.isBlank(status) ? 'Awaiting Confirmation' : status;
                newUser.User_Role__c = userRole;
                newUser.Primary_Account_Type__c = userAccountType;
                newUser.Salt__c = salt;
                newUser.Hash__c = hash;

                Database.SaveResult saveResult = Database.insert(newUser, false);
                if (!saveResult.isSuccess()) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', saveResult.getErrors()[0].getMessage()))));
                    return;
                }

                Chronarpay_User__c createdUser = [
                    SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Company__c, Status__c, User_Role__c,
                    	   Invite_Token__c, Password_Reset_Token__c, Confirmation_Token__c, Number_of_Logins__c, Failed_Login_Count__c, 
                           CreatedDate, LastModifiedDate, Last_Login_Date__c, Last_Password_Change_Date__c, Salt__c, Hash__c, Primary_Account_Type__c
                    FROM Chronarpay_User__c
                    WHERE Id = :saveResult.getId()
                    LIMIT 1
                ];

                ApiResponse apiResponse = new ApiResponse(
                    new List<UserResponse>{ buildUserResponse(createdUser) },
                    buildStatusResponse('S', 'Request successfully processed ,document selected 1')
                );

                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(apiResponse));
                return;
            }

            if (action.equals('modify')) {
                if (String.isBlank(userId)) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'user_id is required for modify'))));
                    return;
                }

                List<Chronarpay_User__c> users = [
                    SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Company__c, Status__c, User_Role__c,
                    	   Invite_Token__c, Password_Reset_Token__c, Confirmation_Token__c, Number_of_Logins__c, Failed_Login_Count__c, 
                           Salt__c, Hash__c, Primary_Account_Type__c
                    FROM Chronarpay_User__c
                    WHERE Id = :userId
                    LIMIT 1
                ];
                if (users.isEmpty()) {
                    res.statusCode = 404;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'User not found'))));
                    return;
                }

                Chronarpay_User__c targetUser = users[0];
                if (String.isNotBlank(login)) {
                    targetUser.Name = login;
                }
                if (String.isNotBlank(firstName)) {
                    targetUser.First_Name__c = firstName;
                }
                if (String.isNotBlank(lastName)) {
                    targetUser.Last_Name__c = lastName;
                }
                if (String.isNotBlank(email)) {
                    targetUser.Email__c = email;
                }
                if (String.isNotBlank(company)) {
                    targetUser.Company__c = company;
                }
                if (String.isNotBlank(invite_token)) {
                    targetUser.Invite_Token__c = invite_token;
                }
                if (String.isNotBlank(password_reset_token)) {
                    targetUser.Password_Reset_Token__c = password_reset_token;
                }
                if (String.isNotBlank(confirmation_token)) {
                    targetUser.Confirmation_Token__c = confirmation_token;
                }
                if (String.isNotBlank(status)) {
                    targetUser.Status__c = status;
                }
                if (String.isNotBlank(userRole)) {
                    targetUser.User_Role__c = userRole;
                }
                if (String.isNotBlank(salt)) {
                    targetUser.Salt__c = salt;
                }
                if (String.isNotBlank(hash)) {
                    targetUser.Hash__c = hash;
                }
                if (String.isNotBlank(userAccountType)) {
                    targetUser.Primary_Account_Type__c = userAccountType;
                }

                Database.SaveResult saveResult = Database.update(targetUser, false);
                if (!saveResult.isSuccess()) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', saveResult.getErrors()[0].getMessage()))));
                    return;
                }

                Chronarpay_User__c refreshedUser = [
                    SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Company__c, Status__c, User_Role__c,
                    	   Invite_Token__c, Password_Reset_Token__c, Confirmation_Token__c, Number_of_Logins__c, Failed_Login_Count__c, 
                           CreatedDate, LastModifiedDate, Last_Login_Date__c, Last_Password_Change_Date__c, Salt__c, Hash__c, Primary_Account_Type__c
                    FROM Chronarpay_User__c
                    WHERE Id = :userId
                    LIMIT 1
                ];

                ApiResponse apiResponse = new ApiResponse(
                    new List<UserResponse>{ buildUserResponse(refreshedUser) },
                    buildStatusResponse('S', 'Request successfully processed ,document selected 1')
                );

                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(apiResponse));
                return;
            }

            if (action.equals('delete')) {
                if (String.isBlank(userId)) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', 'user_id is required for delete'))));
                    return;
                }

                List<Chronarpay_User__c> users = [SELECT Id, Status__c FROM Chronarpay_User__c WHERE Id = :userId LIMIT 1];
                if (!users.isEmpty()) {
                    Chronarpay_User__c userToDeactivate = users[0];
                    delete userToDeactivate;
                }

                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('S', 'Request successfully processed ,document deleted'))));
            }
        } catch (Exception e) {
            res.statusCode = 500;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<UserResponse>(), buildStatusResponse('E', e.getMessage()))));
        }
    }

    private static String getUserIdFromRequest(RestRequest req) {
        String userId = req != null ? req.params.get('user_id') : null;
        if (String.isBlank(userId) && req != null && String.isNotBlank(req.requestURI)) {
            String uri = req.requestURI;
            if (uri.contains('/')) {
                String lastSegment = uri.substringAfterLast('/');
                if (String.isNotBlank(lastSegment) && !lastSegment.equalsIgnoreCase('applicationUserDetail')) {
                    userId = lastSegment;
                }
            }
        }
        return userId;
    }

    private static String getStringValue(Map<String, Object> data, String key) {
        if (data == null || !data.containsKey(key)) {
            return null;
        }
        Object value = data.get(key);
        return value == null ? null : String.valueOf(value);
    }

    private static UserResponse buildUserResponse(Chronarpay_User__c u) {
        UserResponse response = new UserResponse();
        response.application_id = 'CNBSMV01R';
        response.user_id = u.Id;
        response.login = u.Name;
        response.first_name = u.First_Name__c;
        response.last_name = u.Last_Name__c;
        response.company = u.Company__c;
        response.email = u.Email__c;
        response.invite_token = u.Invite_Token__c;
        response.num_logins = u.Number_of_Logins__c != null ? Integer.valueOf(u.Number_of_Logins__c) : 0;
        response.status = u.Status__c;
        response.password_reset_token = u.Password_Reset_Token__c;
        response.salt = u.Salt__c;
        response.hash = u.Hash__c;
        response.primary_account_type_id = u.Primary_Account_Type__c == null ? '' : String.valueOf(u.Primary_Account_Type__c);
        response.user_role = u.User_Role__c;
        response.confirmation_token = u.Confirmation_Token__c;
        response.created_date = u.CreatedDate != null ? u.CreatedDate.format('yyyy-MM-dd') : '';
        response.created_time = u.CreatedDate != null ? u.CreatedDate.format('HH:mm:ss') : '';
        response.updated_date = u.LastModifiedDate != null ? u.LastModifiedDate.format('yyyy-MM-dd') : '';
        response.updated_time = u.LastModifiedDate != null ? u.LastModifiedDate.format('HH:mm:ss') : '';
        response.last_login_date = u.Last_Login_Date__c != null ? u.Last_Login_Date__c.format('yyyy-MM-dd') : '';
        response.last_login_time = u.Last_Login_Date__c != null ? u.Last_Login_Date__c.format('HH:mm:ss') : '';
        response.last_pwd_change_date = u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('yyyy-MM-dd') : '';
        response.last_pwd_change_time = u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('HH:mm:ss') : '';
        response.require_password_change = '';
        response.third_party_id = '';
        response.locked = '';
        response.failed_login_count = u.Failed_Login_Count__c != null ? Integer.valueOf(u.Failed_Login_Count__c) : 0;
        response.last_password_reset = (u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('yyyyMMdd') : '') + (u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('HHmmss') : '');
        response.regional_format = 'US';
        return response;
    }

    private static StatusResponse buildStatusResponse(String messageType, String messageLineString) {
        return new StatusResponse(messageType, '/CNBS/X_API', 10, messageLineString);
    }

    global class ApiResponse {
        public List<UserResponse> data;
        public StatusResponse status;

        public ApiResponse(List<UserResponse> dataList, StatusResponse statusResponse) {
            status = statusResponse;
            data = dataList;
        }
    }

    global class UserResponse {
        public String application_id;
        public String user_id;
        public String login;
        public String first_name;
        public String last_name;
        public String company;
        public String email;
        public String invite_token;
        public Integer num_logins;
        public String status;
        public String password_reset_token;
        public String salt;
        public String hash;
        public String primary_account_type_id;
        public String user_role;
        public String confirmation_token;
        public String created_date;
        public String created_time;
        public String updated_date;
        public String updated_time;
        public String last_login_date;
        public String last_login_time;
        public String last_pwd_change_date;
        public String last_pwd_change_time;
        public String require_password_change;
        public String third_party_id;
        public String locked;
        public Integer failed_login_count;
        public String last_password_reset;
        public String regional_format;
    }

    global class StatusResponse {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;
        public String json;

        public StatusResponse(String messageType, String messageIdentification, Integer messageNumber, String messageLineString) {
            message_type = messageType;
            message_identification = messageIdentification;
            message_number = messageNumber;
            message_line_string = messageLineString;
            json = '';
        }
    }
}