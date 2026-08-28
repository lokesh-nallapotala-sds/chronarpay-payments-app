@RestResource(urlMapping='/accounts/*')
global with sharing class AccountAPI {

    @HttpGet
    global static void getAccountsByUser() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String userId = req.params.get('userId');

            if (String.isBlank(userId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(
                    JSON.serialize(new ErrorResponse('userId is required'))
                );
                return;
            }

            List<Account> accounts = [
                SELECT Id,
                       Name,
                       OwnerId,Type,Sales_Organization__c,distribution_channel__c,division__c,
                        company_code__c,allow_payments__c,allow_deposits__c
                FROM Account
                WHERE OwnerId = :userId
                ORDER BY Name
            ];

            List<AccountResponse> response = new List<AccountResponse>();

            for(Account acc : accounts){
                AccountResponse ar = new AccountResponse();
                ar.accountId = acc.Id;
                ar.accountName = acc.Name;
                ar.userId = acc.OwnerId;
                ar.phone = acc.Phone;
                ar.billingStreet = acc.BillingStreet;
                ar.billingCity = acc.BillingCity;
                ar.billingState = acc.BillingState;
                ar.billingCountry = acc.BillingCountry;
                response.add(ar);
            }

            res.statusCode = 200;
            res.addHeader('Content-Type','application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch(Exception e){
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(
                JSON.serialize(new ErrorResponse(e.getMessage()))
            );
        }
    }

    global class AccountResponse {
        public String accountId;
        public String accountName;
        public String userId;
        public String phone;
        public String billingStreet;
        public String billingCity;
        public String billingState;
        public String billingCountry;
    }

    global class ErrorResponse {
        public String message;

        public ErrorResponse(String msg){
            message = msg;
        }
    }
}