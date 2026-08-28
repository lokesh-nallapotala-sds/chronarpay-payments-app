@IsTest
private class InvoicePaymentControllerTest {

    @TestSetup
    static void setupTestData() {
        Account testAcc = new Account(
            Name = 'Test Payer Account',
            Type = 'Payer',
            AccountNumber = 'ACC-12345'
        );
        insert testAcc;

        Payment_Method__c pm = new Payment_Method__c(
            Account__c = testAcc.Id,
            Card_Token__c = 'pm_test_token_123',
            Card_Type__c = 'VISA',
            Last_Four__c = '4242',
            Cardholder_Name__c = 'Test User',
            Valid_To__c = Date.today().addYears(2),
            Is_Default__c = true
        );
        insert pm;
    }

    @IsTest
    static void testRecordPaymentSuccess() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Payment_Method__c pm = [SELECT Id, Card_Token__c FROM Payment_Method__c LIMIT 1];

        Test.startTest();
        Id paymentId = InvoicePaymentController.recordPayment(
            acc.Id,
            250.00,
            250.00,
            'USD',
            'pi_success_123',
            pm.Card_Token__c,
            'Paid',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, paymentId, 'Payment record should be created');

        Payment__c p = [
            SELECT Id, Account__c, Amount__c, Amount_Received__c, Currency__c,
                   Payment_Method__c, Status__c, Payment_Intent_Id__c, Failure_Reason__c
            FROM Payment__c
            WHERE Id = :paymentId
        ];

        System.assertEquals(acc.Id, p.Account__c, 'Account ID should match');
        System.assertEquals(250.00, p.Amount__c, 'Amount should match');
        System.assertEquals(250.00, p.Amount_Received__c, 'Amount received should match');
        System.assertEquals('USD', p.Currency__c, 'Currency should match');
        System.assertEquals('Paid', p.Status__c, 'Status should be Paid');
        System.assertEquals('pi_success_123', p.Payment_Intent_Id__c, 'PaymentIntent ID should match');
        System.assertEquals(pm.Id, p.Payment_Method__c, 'Payment method lookup should be linked');
        System.assertEquals(null, p.Failure_Reason__c, 'Failure reason should be null for success');
    }

    @IsTest
    static void testRecordPaymentFailure() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id paymentId = InvoicePaymentController.recordPayment(
            acc.Id,
            100.50,
            0.00,
            'USD',
            'pi_failed_456',
            null,
            'Failed',
            'Your card was declined by the issuer.'
        );
        Test.stopTest();

        System.assertNotEquals(null, paymentId, 'Payment record should be created');

        Payment__c p = [
            SELECT Id, Account__c, Amount__c, Amount_Received__c, Status__c,
                   Payment_Intent_Id__c, Failure_Reason__c
            FROM Payment__c
            WHERE Id = :paymentId
        ];

        System.assertEquals(acc.Id, p.Account__c, 'Account ID should match');
        System.assertEquals(100.50, p.Amount__c, 'Amount should match');
        System.assertEquals(0.00, p.Amount_Received__c, 'Amount received should be 0');
        System.assertEquals('Failed', p.Status__c, 'Status should be Failed');
        System.assertEquals('pi_failed_456', p.Payment_Intent_Id__c, 'PaymentIntent ID should match');
        System.assertEquals('Your card was declined by the issuer.', p.Failure_Reason__c, 'Failure reason should match');
    }

    @IsTest
    static void testRecordPaymentIdempotencyUpdate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // First call: pending/processing
        Id firstId = InvoicePaymentController.recordPayment(
            acc.Id,
            300.00,
            0.00,
            'USD',
            'pi_idempotent_789',
            null,
            'Processing',
            null
        );

        // Second call: confirmed succeeded
        Id secondId = InvoicePaymentController.recordPayment(
            acc.Id,
            300.00,
            300.00,
            'USD',
            'pi_idempotent_789',
            'pm_test_token_123',
            'succeeded',
            null
        );
        Test.stopTest();

        System.assertEquals(firstId, secondId, 'Subsequent call with same PaymentIntent ID should update existing record');

        Payment__c p = [
            SELECT Id, Amount__c, Amount_Received__c, Status__c, Payment_Method__c
            FROM Payment__c
            WHERE Id = :firstId
        ];

        System.assertEquals('Paid', p.Status__c, 'Status should be updated to Paid');
        System.assertEquals(300.00, p.Amount_Received__c, 'Amount received should be updated');
        System.assertNotEquals(null, p.Payment_Method__c, 'Payment method should be linked on update');
    }

    @IsTest
    static void testRecordPaymentNullAccount() {
        Test.startTest();
        Id paymentId = InvoicePaymentController.recordPayment(
            null,
            100.00,
            100.00,
            'USD',
            'pi_no_account',
            null,
            'Paid',
            null
        );
        Test.stopTest();

        System.assertEquals(null, paymentId, 'Should return null when accountId is null');
    }
}