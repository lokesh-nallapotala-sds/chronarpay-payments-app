@RestResource(urlMapping='/getUserAccounts/*')
global with sharing class GetUserAccountsAPI {

    @HttpGet
    global static void getAccounts() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }
        res.addHeader('Content-Type', 'application/json');

        try {
            String userId = req.params.get('userId');
            if (String.isBlank(userId)) {
                String uri = req.requestURI;
                userId = uri.substring(uri.lastIndexOf('/') + 1);
            }

            if (String.isBlank(userId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('userId parameter is required.')));
                return;
            }

            Id userSfId;
            try {
                userSfId = (Id) userId;
            } catch (StringException e) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid User ID: ' + userId)));
                return;
            }

            List<User> users = [
                SELECT Id, Username, FirstName, LastName, Email, CompanyName, IsActive, Profile.Name
                FROM User
                WHERE Id = :userSfId
                LIMIT 1
            ];

            if (users.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('User not found: ' + userId)));
                return;
            }

            User u = users[0];

            // Query Application User Account Junction Records
            List<Application_User_Account__c> junctionRecords = [
                SELECT Account__c, Account__r.Name, Account__r.Type, Account__r.AccountNumber, Account__r.account_id__c, Is_Primary__c
                FROM Application_User_Account__c
                WHERE User__c = :u.Id
            ];

            Set<Id> associatedAccountIds = new Set<Id>();
            for (Application_User_Account__c aua : junctionRecords) {
                if (aua.Account__c != null) {
                    associatedAccountIds.add(aua.Account__c);
                }
            }

            // Determine user's primary account type
            String primaryAccountType = null;
            for (Application_User_Account__c aua : junctionRecords) {
                if (aua.Is_Primary__c && aua.Account__r.Type != null) {
                    primaryAccountType = aua.Account__r.Type;
                    break;
                }
            }
            if (primaryAccountType == null) {
                for (Application_User_Account__c aua : junctionRecords) {
                    if (aua.Account__r.Type == 'Payer') {
                        primaryAccountType = 'Payer';
                        break;
                    }
                }
            }
            if (primaryAccountType == null) {
                for (Application_User_Account__c aua : junctionRecords) {
                    if (aua.Account__r.Type == 'Sold-To') {
                        primaryAccountType = 'Sold-To';
                        break;
                    }
                }
            }
            if (primaryAccountType == null && !junctionRecords.isEmpty()) {
                primaryAccountType = junctionRecords[0].Account__r.Type;
            }

            // Track related accounts mapping to their directly associated parent/child source
            Map<Id, Id> relatedToDirectIdMap = new Map<Id, Id>();
            for (Id directId : associatedAccountIds) {
                relatedToDirectIdMap.put(directId, directId);
            }

            // If a user's primary account type is Payer, get parent and child accounts of the associated accounts
            if (primaryAccountType == 'Payer' && !associatedAccountIds.isEmpty()) {
                // 1. Traverse parent accounts (traverse up the hierarchy)
                Set<Id> currentLevelIds = new Set<Id>(associatedAccountIds);
                while (!currentLevelIds.isEmpty()) {
                    Map<Id, Account> accountsWithParents = new Map<Id, Account>([
                        SELECT Id, ParentId FROM Account WHERE Id IN :currentLevelIds AND ParentId != null
                    ]);
                    currentLevelIds.clear();
                    for (Account acc : accountsWithParents.values()) {
                        if (!relatedToDirectIdMap.containsKey(acc.ParentId)) {
                            relatedToDirectIdMap.put(acc.ParentId, relatedToDirectIdMap.get(acc.Id));
                            currentLevelIds.add(acc.ParentId);
                        }
                    }
                }

                // 2. Traverse child accounts (traverse down the hierarchy)
                currentLevelIds = new Set<Id>(associatedAccountIds);
                while (!currentLevelIds.isEmpty()) {
                    Map<Id, Account> childAccounts = new Map<Id, Account>([
                        SELECT Id, ParentId FROM Account WHERE ParentId IN :currentLevelIds
                    ]);
                    currentLevelIds.clear();
                    for (Account child : childAccounts.values()) {
                        if (!relatedToDirectIdMap.containsKey(child.Id)) {
                            relatedToDirectIdMap.put(child.Id, relatedToDirectIdMap.get(child.ParentId));
                            currentLevelIds.add(child.Id);
                        }
                    }
                }
            }

            // Query all resolved accounts
            Map<Id, Account> allAccountsMap = new Map<Id, Account>([
                SELECT Id, Name, AccountNumber, account_id__c
                FROM Account
                WHERE Id IN :relatedToDirectIdMap.keySet()
                ORDER BY Name
            ]);

            List<LinkedAccount> linkedAccountsList = new List<LinkedAccount>();
            for (Account acc : allAccountsMap.values()) {
                Id directId = relatedToDirectIdMap.get(acc.Id);
                Account directAcc = allAccountsMap.get(directId);

                String primaryAccountVal = '';
                if (directAcc != null) {
                    primaryAccountVal = String.isNotBlank(directAcc.AccountNumber) 
                        ? directAcc.AccountNumber 
                        : directAcc.account_id__c;
                }
                if (String.isBlank(primaryAccountVal)) {
                    primaryAccountVal = String.isNotBlank(acc.AccountNumber)
                        ? acc.AccountNumber
                        : acc.account_id__c;
                }
                if (String.isBlank(primaryAccountVal)) {
                    primaryAccountVal = acc.Id;
                }

                linkedAccountsList.add(new LinkedAccount(primaryAccountVal, acc.Name));
            }

            UserResponse response = new UserResponse();
            response.userId = u.Id;
            response.login = u.Username;
            response.firstName = u.FirstName;
            response.lastName = u.LastName;
            response.email = u.Email;
            response.company = u.CompanyName;
            response.primaryAccountType = primaryAccountType;
            response.status = u.IsActive ? 'active' : 'inactive';
            
            String userRole = 'user';
            if (u.Profile.Name != null && u.Profile.Name.contains('Admin')) {
                userRole = 'admin';
            }
            response.role = userRole;
            response.regionalFormat = 'nu';
            response.linkedAccounts = linkedAccountsList;

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(e.getMessage())));
        }
    }

    global class UserResponse {
        public String userId;
        public String login;
        public String firstName;
        public String lastName;
        public String email;
        public String company;
        public String primaryAccountType;
        public String status;
        public String role;
        public String regionalFormat;
        public List<LinkedAccount> linkedAccounts;
    }

    global class LinkedAccount {
        public String primaryAccount;
        public String name;
        
        global LinkedAccount(String primaryAccount, String name) {
            this.primaryAccount = primaryAccount;
            this.name = name;
        }
    }

    global class ErrorResponse {
        public String message;
        public ErrorResponse(String msg) {
            this.message = msg;
        }
    }
}