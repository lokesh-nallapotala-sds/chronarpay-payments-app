@isTest
public class ChronarPayControllerTest {
    
    @isTest
    static void testGetBillingAccounts() {
        Test.startTest();
        List<Account> accounts = ChronarPayController.getBillingAccounts();
        Test.stopTest();
        System.assertNotEquals(null, accounts, 'Accounts list should not be null');
        System.assert(accounts.size() > 0, 'Accounts list should not be empty');
    }
    
    @isTest
    static void testGetInvoiceDashboardData() {
        List<Account> accounts = ChronarPayController.getBillingAccounts();
        String targetAccountId = accounts[0].Id;
        
        Test.startTest();
        // Test All filter
        Map<String, Object> dataAll = ChronarPayController.getInvoiceDashboardData(targetAccountId, 'All');
        System.assertNotEquals(null, dataAll, 'Dashboard data should not be null');
        System.assert(dataAll.containsKey('invoices'), 'Dashboard data should contain invoices key');
        
        // Test Open filter
        Map<String, Object> dataOpen = ChronarPayController.getInvoiceDashboardData(targetAccountId, 'Open');
        System.assertNotEquals(null, dataOpen, 'Dashboard data should not be null for Open filter');
        
        // Test Past Due filter
        Map<String, Object> dataPastDue = ChronarPayController.getInvoiceDashboardData(targetAccountId, 'Past Due');
        System.assertNotEquals(null, dataPastDue, 'Dashboard data should not be null for Past Due filter');
        
        // Test Paid filter
        Map<String, Object> dataPaid = ChronarPayController.getInvoiceDashboardData(targetAccountId, 'Paid');
        System.assertNotEquals(null, dataPaid, 'Dashboard data should not be null for Paid filter');
        Test.stopTest();
    }
    
    @isTest
    static void testCreatePaymentRecord() {
        // Create an Account for createPaymentRecord to fetch
        Account acc = new Account(Name = 'Test Billing Account');
        insert acc;
        
        Test.startTest();
        // Try creating a payment record
        String paymentId = ChronarPayController.createPaymentRecord('MOCK_INV_0090040946', 500.0, null, 'Test Cardholder', '4242424242424242', '12', '2030', '123');
        Test.stopTest();
        
        System.assertNotEquals(null, paymentId, 'Payment record ID should be returned');
        
        // Verify payment record was inserted
        List<Payment> payments = [SELECT Id, Amount, Status FROM Payment WHERE Id = :paymentId];
        System.assertEquals(1, payments.size(), 'Exactly one Payment record should exist');
        System.assertEquals(500.0, payments[0].Amount, 'Payment amount should be 500.0');
        System.assertEquals('Processed', payments[0].Status, 'Payment status should be Processed');
    }
}