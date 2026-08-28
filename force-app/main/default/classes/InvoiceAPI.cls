@RestResource(urlMapping='/invoices/*')
global with sharing class InvoiceAPI {

    @HttpGet
    global static void getInvoicesByUser() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {

            String userId = req.params.get('userId');

            if (String.isBlank(userId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"message":"userId is required"}');
                return;
            }

            // Get all Accounts for the User
            List<Account> accounts = [
                SELECT Id, Name
                FROM Account
                WHERE OwnerId = :userId
            ];

            if(accounts.isEmpty()){
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('[]');
                return;
            }

            Set<Id> accountIds = new Set<Id>();

            for(Account acc : accounts){
                accountIds.add(acc.Id);
            }

            // Get Invoices
            List<Invoice__c> invoices = [
                SELECT Id,
                       Name,
                       Payer_Account__r.Id,
                       Payer_Account__r.Name
                FROM Invoice__c
                WHERE Payer_Account__c IN :accountIds
            ];

            List<InvoiceWrapper> response = new List<InvoiceWrapper>();

            for(Invoice__c inv : invoices){

                InvoiceWrapper w = new InvoiceWrapper();

                w.invoiceId = inv.Id;
                w.invoiceName = inv.Name;
                w.accountId = inv.Payer_Account__r.Id;
                w.accountName = inv.Payer_Account__r.Name;

                response.add(w);
            }

            res.statusCode = 200;
            res.addHeader('Content-Type','application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(response));

        }
        catch(Exception e){

            res.statusCode = 500;
            res.responseBody = Blob.valueOf(
                '{"message":"' + e.getMessage() + '"}'
            );
        }
    }

    global class InvoiceWrapper{

        public Id invoiceId;
        public String invoiceName;
        public String invoiceNumber;
        public Date invoiceDate;
        public Date dueDate;
        public Decimal amount;
        public String status;
        public Id accountId;
        public String accountName;

    }

}