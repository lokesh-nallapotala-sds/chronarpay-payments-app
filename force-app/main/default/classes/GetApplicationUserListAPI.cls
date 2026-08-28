@RestResource(urlMapping='/getApplicationUserList/*')
/**
 * REST API for exposing Application User information to external consumers.
 * Based on CNBS API documentation: /cnbs/v1/apu/users
 */
global with sharing class GetApplicationUserListAPI {

    /**
     * Returns a list of Application Users based on optional search parameters.
     * GET /getApplicationUserList
     * 
     * Optional Parameters:
     * - user_id: GUID identifying an application user
     * - login: Login name
     * - email: Email address
     * - user_status: User status (active, inactive, etc.)
     * - profile: User profile
     * - third_party_id: Third party identifier
     * - password_reset_token: Password reset token
     * - confirmation_token: Confirmation token
     * - invite_token: Invite token
     * - search_string: Generic search string
     */
    @HttpGet
    global static void getApplicationUsers() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            // Extract optional parameters
            String userId = req != null ? req.params.get('user_id') : null;
            String login = req != null ? req.params.get('login') : null;
            String email = req != null ? req.params.get('email') : null;
            String userStatus = req != null ? req.params.get('user_status') : null;
            String profile = req != null ? req.params.get('profile') : null;
            String thirdPartyId = req != null ? req.params.get('third_party_id') : null;
            String passwordResetToken = req != null ? req.params.get('password_reset_token') : null;
            String confirmationToken = req != null ? req.params.get('confirmation_token') : null;
            String inviteToken = req != null ? req.params.get('invite_token') : null;
            String searchString = req != null ? req.params.get('search_string') : null;

            // Build dynamic SOQL query against Chronarpay_User__c
            String soql = 'SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Status__c, Salt__c, Hash__c, User_Role__c, Company__c, Primary_Account_Type__c, ' +
                          'Invite_Token__c, Password_Reset_Token__c, Confirmation_Token__c, Number_of_Logins__c, Failed_Login_Count__c, ' +
                          'CreatedDate, LastModifiedDate, Last_Login_Date__c, Last_Password_Change_Date__c FROM Chronarpay_User__c WHERE Id != null';

            // Add filters based on parameters
            if (String.isNotBlank(userId)) {
                soql += ' AND Id = :userId';
            }
            if (String.isNotBlank(login)) {
                soql += ' AND Name = :login';
            }
            if (String.isNotBlank(email)) {
                soql += ' AND Email__c = :email';
            }
            if (String.isNotBlank(userStatus)) {
                soql += ' AND Status__c = :userStatus';
            }
            if (String.isNotBlank(profile)) {
                soql += ' AND User_Role__c = :profile';
            }
            if (String.isNotBlank(inviteToken)) {
                soql += ' AND Invite_Token__c = :inviteToken';
            }
            if (String.isNotBlank(passwordResetToken)) {
                soql += ' AND Password_Reset_Token__c = :passwordResetToken';
            }
            if (String.isNotBlank(confirmationToken)) {
                soql += ' AND Confirmation_Token__c = :confirmationToken';
            }
            if (String.isNotBlank(searchString)) {
                String searchPattern = '%' + searchString + '%';
                soql += ' AND (Name LIKE :searchPattern OR First_Name__c LIKE :searchPattern OR Last_Name__c LIKE :searchPattern OR Email__c LIKE :searchPattern)';
            }

            soql += ' ORDER BY Name LIMIT 1000';

            List<Chronarpay_User__c> users = Database.query(soql);
            List<UserResponse> responseData = new List<UserResponse>();

            Set<Id> userIds = new Set<Id>();
            for (Chronarpay_User__c u : users) {
                userIds.add(u.Id);
            }

            Map<Id, List<LinkedAccount>> userLinkedAccountsMap = new Map<Id, List<LinkedAccount>>();
            if (!userIds.isEmpty()) {
                List<Application_User_Account__c> junctionRecords = [
                    SELECT Chronarpay_User__c, Account__c, Account__r.Name, Account__r.AccountNumber, Account__r.account_id__c
                    FROM Application_User_Account__c
                    WHERE Chronarpay_User__c IN :userIds
                ];
                for (Application_User_Account__c aua : junctionRecords) {
                    if (aua.Account__c != null) {
                        Id ownerId = aua.Chronarpay_User__c != null ? aua.Chronarpay_User__c : aua.User__c;
                        if (!userLinkedAccountsMap.containsKey(ownerId)) {
                            userLinkedAccountsMap.put(ownerId, new List<LinkedAccount>());
                        }
                        String primaryAcc = String.isNotBlank(aua.Account__r.AccountNumber) 
                            ? aua.Account__r.AccountNumber 
                            : (String.isNotBlank(aua.Account__r.account_id__c) ? aua.Account__r.account_id__c : aua.Account__c);
                        userLinkedAccountsMap.get(ownerId).add(new LinkedAccount(primaryAcc, aua.Account__r.Name));
                    }
                }
            }

            for (Chronarpay_User__c u : users) {
                List<LinkedAccount> linkedAccs = userLinkedAccountsMap.get(u.Id);
                responseData.add(buildUserResponse(u, linkedAccs));
            }

            ApiResponse apiResponse = new ApiResponse(
                responseData,
                buildStatusResponse('S', 'Request successfully processed')
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

    /**
     * Builds a UserResponse object from a Salesforce User record
     */
    private static UserResponse buildUserResponse(Chronarpay_User__c u, List<LinkedAccount> linkedAccs) {
        UserResponse response = new UserResponse();
        response.user_id = u.Id;
        response.login = u.Name;
        response.first_name = u.First_Name__c;
        response.last_name = u.Last_Name__c;
        response.email = u.Email__c;
        response.company = u.Company__c;
        response.status = String.isNotBlank(u.Status__c) ? u.Status__c.toLowerCase() : 'inactive';
        response.user_role = u.User_Role__c;
        response.created_date = u.CreatedDate != null ? u.CreatedDate.format('yyyyMMdd') : '';
        response.created_time = u.CreatedDate != null ? u.CreatedDate.format('HHmmss') : '';
        response.updated_date = u.LastModifiedDate != null ? u.LastModifiedDate.format('yyyyMMdd') : '';
        response.updated_time = u.LastModifiedDate != null ? u.LastModifiedDate.format('HHmmss') : '';
        response.last_login_date = u.Last_Login_Date__c != null ? u.Last_Login_Date__c.format('yyyyMMdd') : '';
        response.last_login_time = u.Last_Login_Date__c != null ? u.Last_Login_Date__c.format('HHmmss') : '';
        response.last_pwd_change_date = u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('yyyyMMdd') : '';
        response.last_pwd_change_time = u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('HHmmss') : '';
        response.locked = (String.isBlank(u.Status__c) || u.Status__c.equalsIgnoreCase('Active')) ? '' : 'locked';
        response.regional_format = 'US';
        response.application_id = 'CNBSMV01R';
        response.num_logins = u.Number_of_Logins__c != null ? Integer.valueOf(u.Number_of_Logins__c) : 0;
        response.invite_token = u.Invite_Token__c;
        response.password_reset_token = u.Password_Reset_Token__c;
        response.salt = u.Salt__c;
        response.hash = u.Hash__c;
        response.primary_account_type_id = u.Primary_Account_Type__c;
        response.confirmation_token = u.Confirmation_Token__c;
        response.require_password_change = '';
        response.third_party_id = '';
        response.failed_login_count = u.Failed_Login_Count__c != null ? Integer.valueOf(u.Failed_Login_Count__c) : 0;
        response.last_password_reset = (u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('yyyyMMdd') : '') + (u.Last_Password_Change_Date__c != null ? u.Last_Password_Change_Date__c.format('HHmmss') : '');
        response.linked_accounts = linkedAccs != null ? linkedAccs : new List<LinkedAccount>();
        return response;
    }

    /**
     * Builds a standard status response
     */
    private static StatusResponse buildStatusResponse(String messageType, String messageLineString) {
        return new StatusResponse(messageType, '/CNBS/X_API', 10, messageLineString);
    }

    /**
     * Wrapper class for API response
     */
    global class ApiResponse {
        public List<UserResponse> data;
        public StatusResponse status;

        public ApiResponse(List<UserResponse> dataList, StatusResponse statusResponse) {
            status = statusResponse;
            data = dataList;
        }
    }

    /**
     * User response object matching the CNBS API contract
     */
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
        public List<LinkedAccount> linked_accounts;
    }

    /**
     * Linked account information
     */
    global class LinkedAccount {
        public String primary_account;
        public String name;

        public LinkedAccount(String primaryAccount, String accountName) {
            primary_account = primaryAccount;
            name = accountName;
        }
    }

    /**
     * Status response object
     */
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