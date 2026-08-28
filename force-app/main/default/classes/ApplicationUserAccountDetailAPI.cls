@RestResource(urlMapping='/applicationUserAccountDetail/*')
/**
 * New API for Application User Account Detail based on the documented CNBS endpoint contract.
 */
global with sharing class ApplicationUserAccountDetailAPI {

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
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'Request body is required'))));
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
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'action and data are required'))));
                return;
            }

            String userId = data.containsKey('user_id') ? String.valueOf(data.get('user_id')) : null;
            String accountId = data.containsKey('account_id') ? String.valueOf(data.get('account_id')) : null;
            String accountType = data.containsKey('account_type') ? String.valueOf(data.get('account_type')) : null;
            String primaryAccount = data.containsKey('primary_account') ? String.valueOf(data.get('primary_account')) : null;
            String salesOrganization = data.containsKey('sales_organization') ? String.valueOf(data.get('sales_organization')) : null;
            String distributionChannel = data.containsKey('distribution_channel') ? String.valueOf(data.get('distribution_channel')) : null;
            String division = data.containsKey('division') ? String.valueOf(data.get('division')) : null;
            String companyCode = data.containsKey('company_code') ? String.valueOf(data.get('company_code')) : null;
            Boolean allowPayments = data.containsKey('allow_payments') ? parseBooleanValue(data.get('allow_payments')) : null;
            Boolean allowDeposits = data.containsKey('allow_deposits') ? parseBooleanValue(data.get('allow_deposits')) : null;

            if (String.isBlank(userId)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'user_id is required'))));
                return;
            }

            List<Chronarpay_User__c> users = [
                SELECT Id, Primary_Account_Type__c
                FROM Chronarpay_User__c
                WHERE Id = :userId
                LIMIT 1
            ];
            if (users.isEmpty() || String.isBlank(users[0].Primary_Account_Type__c)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'User primary account type is required'))));
                return;
            }
            String userPrimaryAccountType = users[0].Primary_Account_Type__c;

            if (!action.equalsIgnoreCase('create') && !action.equalsIgnoreCase('modify') && !action.equalsIgnoreCase('delete')) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'Unsupported action'))));
                return;
            }

            String linkedAccountId = null;
            if (action.equalsIgnoreCase('create')) {
                if (String.isBlank(accountId)) {
                    List<Account> linkedAccounts = [
                        SELECT Id
                        FROM Account
                        WHERE Sales_Organization__c = :salesOrganization
                          AND distribution_channel__c = :distributionChannel
                          AND division__c = :division
                          AND company_code__c = :companyCode
                          AND Type = :userPrimaryAccountType
                        WITH USER_MODE
                        LIMIT 1
                    ];
                    if (linkedAccounts.isEmpty()) {
                        res.statusCode = 400;
                        res.addHeader('Content-Type', 'application/json');
                        res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'No matching account found for supplied sales area and primary account type'))));
                        return;
                    }
                    linkedAccountId = linkedAccounts[0].Id;
                } else {
                    List<Account> linkedAccounts = [
                        SELECT Id
                        FROM Account
                        WHERE Id = :accountId
                          AND Type = :userPrimaryAccountType
                        WITH USER_MODE
                        LIMIT 1
                    ];
                    if (linkedAccounts.isEmpty()) {
                        res.statusCode = 400;
                        res.addHeader('Content-Type', 'application/json');
                        res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'Account not found for supplied account_id'))));
                        return;
                    }
                    linkedAccountId = linkedAccounts[0].Id;
                }
            } else if (action.equalsIgnoreCase('modify')) {
                if (String.isBlank(accountId)) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'account_id is required for modify'))));
                    return;
                }

                List<Account> linkedAccounts = [
                    SELECT Id
                    FROM Account
                    WHERE Id = :accountId
                      AND Type = :userPrimaryAccountType
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (linkedAccounts.isEmpty()) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'Account not found for supplied account_id'))));
                    return;
                }
                linkedAccountId = linkedAccounts[0].Id;
            } else {
                if (String.isBlank(accountId)) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'account_id is required for delete'))));
                    return;
                }
                linkedAccountId = accountId;
            }

            if (action.equalsIgnoreCase('delete')) {
                List<Application_User_Account__c> existingJunctions = [
                    SELECT Id, Chronarpay_User__c, Account__c, Is_Primary__c,
                    Account__r.Sales_Organization__c, Account__r.distribution_channel__c, Account__r.division__c, Account__r.company_code__c
                    FROM Application_User_Account__c
                    WHERE Chronarpay_User__c = :userId
                      AND Account__r.Sales_Organization__c = :salesOrganization
                      AND Account__r.distribution_channel__c = :distributionChannel
                      AND Account__r.division__c = :division
                      AND Account__r.company_code__c = :companyCode
                      AND Account__r.Type = :userPrimaryAccountType
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!existingJunctions.isEmpty()) {
                    delete existingJunctions;
                }

                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('S', 'Request successfully processed ,document deleted'))));
                return;
            }

            Application_User_Account__c junctionRecord;
            List<Application_User_Account__c> existingJunctions = new List<Application_User_Account__c>();

            List<Account> linkTheAccounts = [
                SELECT Id, Type, Sales_Organization__c, distribution_channel__c, division__c, company_code__c
                FROM Account
                WHERE Sales_Organization__c = :salesOrganization
                  AND distribution_channel__c = :distributionChannel
                  AND division__c = :division
                  AND company_code__c = :companyCode
                  AND Type = :userPrimaryAccountType
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (action.equalsIgnoreCase('create')) {
                existingJunctions = [
                    SELECT Id, Chronarpay_User__c, Account__c, Is_Primary__c,
                    Account__r.Sales_Organization__c, Account__r.distribution_channel__c, Account__r.division__c, Account__r.company_code__c
                    FROM Application_User_Account__c
                    WHERE Chronarpay_User__c = :userId
                      AND Account__r.Sales_Organization__c = :salesOrganization
                      AND Account__r.distribution_channel__c = :distributionChannel
                      AND Account__r.division__c = :division
                      AND Account__r.company_code__c = :companyCode
                      AND Account__r.Type = :userPrimaryAccountType
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (!existingJunctions.isEmpty()) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'Relation already exists for the supplied user and sales area'))));
                    return;
                }

                junctionRecord = new Application_User_Account__c();
            } else if (action.equalsIgnoreCase('modify')) {
                existingJunctions = [
                    SELECT Id, Chronarpay_User__c, Account__c, Is_Primary__c,
                    Account__r.Sales_Organization__c, Account__r.distribution_channel__c, Account__r.division__c, Account__r.company_code__c
                    FROM Application_User_Account__c
                    WHERE Chronarpay_User__c = :userId
                      AND Account__c = :accountId
                      //AND Account__r.distribution_channel__c = :distributionChannel
                      //AND Account__r.division__c = :division
                      //AND Account__r.company_code__c = :companyCode
                      //AND Account__r.Type = :userPrimaryAccountType
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (existingJunctions.isEmpty()) {
                    res.statusCode = 400;
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', 'Application user account not found'))));
                    return;
                }
                
                junctionRecord = existingJunctions[0];
            }

            junctionRecord.Chronarpay_User__c = userId;
            junctionRecord.Account__c = linkTheAccounts[0] != null ? linkTheAccounts[0].Id : junctionRecord.Account__c;
            junctionRecord.Is_Primary__c = String.isNotBlank(primaryAccount);

            if (action.equalsIgnoreCase('create')) {
                insert junctionRecord;
            } else if (action.equalsIgnoreCase('modify')) {
                update junctionRecord;
            }

            Application_User_Account__c refreshedJunction = [
                SELECT Id, Chronarpay_User__c, Account__c, Is_Primary__c,
                       Account__r.Sales_Organization__c, Account__r.distribution_channel__c, Account__r.division__c, Account__r.company_code__c
                FROM Application_User_Account__c
                WHERE Id = :junctionRecord.Id
                WITH USER_MODE
                LIMIT 1
            ];

            List<AccountResponse> responseData = new List<AccountResponse>{ buildAccountResponse(refreshedJunction, accountType) };
            ApiResponse apiResponse = new ApiResponse(responseData, buildStatusResponse('S', 'Request successfully processed ,document selected 1'));

            res.statusCode = 200;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(apiResponse));
        } catch (Exception e) {
            res.statusCode = 500;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<AccountResponse>(), buildStatusResponse('E', e.getMessage()))));
        }
    }

    private static StatusResponse buildStatusResponse(String messageType, String messageLineString) {
        return new StatusResponse(messageType, '/CNBS/X_API', 10, messageLineString);
    }

    private static AccountResponse buildAccountResponse(Application_User_Account__c junctionRecord, String accountType) {
        AccountResponse response = new AccountResponse();
        response.account_id = junctionRecord.Account__c;
        response.user_id = junctionRecord.Chronarpay_User__c;
        response.account_type = accountType;
        response.primary_account = junctionRecord.Account__r != null ? junctionRecord.Account__r.AccountNumber : null;//junctionRecord.Is_Primary__c ? 'X' : '';
        response.sales_organization = junctionRecord.Account__r != null ? junctionRecord.Account__r.Sales_Organization__c : null;
        response.distribution_channel = junctionRecord.Account__r != null ? junctionRecord.Account__r.distribution_channel__c : null;
        response.division = junctionRecord.Account__r != null ? junctionRecord.Account__r.division__c : null;
        response.company_code = junctionRecord.Account__r != null ? junctionRecord.Account__r.company_code__c : null;
        response.allow_payments = null;
        response.allow_deposits = null;
        return response;
    }

    private static Boolean parseBooleanValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String stringValue = String.valueOf(value).trim();
        if (String.isBlank(stringValue)) {
            return null;
        }
        return stringValue.equalsIgnoreCase('X') || stringValue.equalsIgnoreCase('true') || stringValue.equalsIgnoreCase('1');
    }

    private static String toStringValue(Boolean value) {
        if (value == null) {
            return null;
        }
        return value ? 'X' : '';
    }

    global class ApiResponse {
        public List<AccountResponse> data;
        public StatusResponse status;

        public ApiResponse(List<AccountResponse> dataList, StatusResponse statusResponse) {
            status = statusResponse;
            data = dataList;
        }
    }

    global class AccountResponse {
        public String account_id;
        public String user_id;
        public String account_type;
        public String primary_account;
        public String sales_organization;
        public String distribution_channel;
        public String division;
        public String company_code;
        public String allow_payments;
        public String allow_deposits;
    }

    global class StatusResponse {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;

        public StatusResponse(String messageType, String messageIdentification, Integer messageNumber, String messageLineString) {
            message_type = messageType;
            message_identification = messageIdentification;
            message_number = messageNumber;
            message_line_string = messageLineString;
        }
    }
}