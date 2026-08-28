@IsTest
private class InvoiceListControllerTest {

    @TestSetup
    static void setupTestData() {
        Account payer = new Account(
            Name = 'Payer Account 1',
            Type = 'Payer',
            AccountNumber = 'PAYER-001',
            sales_organization__c = '1000'
        );
        insert payer;

        Account soldTo = new Account(
            Name = 'Sold To Account 1',
            Type = 'Customer',
            AccountNumber = 'SOLDTO-001',
            sales_organization__c = '1000'
        );
        insert soldTo;

        insert new Account_Relationship__c(
            Payer_Account__c = payer.Id,
            SoldTo_Account__c = soldTo.Id
        );

        Invoice__c inv = new Invoice__c(
            Payer_Account__c = payer.Id,
            Sold_To_Account__c = soldTo.Id,
            Billing_Document_Number__c = 'INV-1001',
            Reference_Document_Number__c = 'REF-1001',
            Document_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Total_Amount__c = 500.00,
            Open_Amount__c = 500.00,
            Paid_Amount__c = 0.00,
            Currency_Key__c = 'USD'
        );
        insert inv;
    }

    @IsTest
    static void testGetPayerAccounts() {
        Test.startTest();
        List<InvoiceListController.PayerAccountWrapper> wrappers = InvoiceListController.getPayerAccounts();
        Test.stopTest();

        System.assertNotEquals(0, wrappers.size(), 'Should return payer accounts with invoices');
    }

    @IsTest
    static void testGetInvoicesByPayerAccountId() {
        Account payer = [SELECT Id FROM Account WHERE AccountNumber = 'PAYER-001' LIMIT 1];

        Test.startTest();
        List<InvoiceListController.InvoiceWrapper> invoices = InvoiceListController.getInvoicesByPayerAccountId(payer.Id);
        Test.stopTest();

        System.assertEquals(1, invoices.size(), 'Should return 1 invoice');
        System.assertEquals('INV-1001', invoices[0].billingDocumentNumber);
        System.assertEquals('SOLDTO-001', invoices[0].soldToAccountNumber);
    }

    @IsTest
    static void testGetSoldToAccountsByPayerAccountId() {
        Account payer = [SELECT Id FROM Account WHERE AccountNumber = 'PAYER-001' LIMIT 1];

        Test.startTest();
        List<InvoiceListController.SoldToAccountWrapper> soldTos = InvoiceListController.getSoldToAccountsByPayerAccountId(payer.Id);
        Test.stopTest();

        System.assertNotEquals(0, soldTos.size(), 'Should return associated sold to accounts');
        System.assertEquals('SOLDTO-001', soldTos[0].accountNumber);
    }

    @IsTest
    static void testApplyInvoicePaymentsJson() {
        Invoice__c inv = [SELECT Id FROM Invoice__c LIMIT 1];
        String jsonPayload = '[{"invoiceId":"' + inv.Id + '","paymentAmount":200.00}]';

        Test.startTest();
        Integer updatedCount = InvoiceListController.applyInvoicePaymentsJson(jsonPayload);
        Test.stopTest();

        System.assertEquals(1, updatedCount, 'Should update 1 invoice');
        Invoice__c updatedInv = [SELECT Open_Amount__c, Paid_Amount__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(300.00, updatedInv.Open_Amount__c);
        System.assertEquals(200.00, updatedInv.Paid_Amount__c);
    }
}