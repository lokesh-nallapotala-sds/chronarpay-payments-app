@IsTest
private class PayerAllowedPaymentCardsAPITest {

    @IsTest
    static void testReturnsAllowedPaymentCardsForPayerAccount() {
        Account payerAcc = new Account(
            Name = 'Payer Account',
            AccountNumber = '3050',
            account_id__c = '3050',
            company_code__c = '3000',
            Type = 'Payer'
        );
        insert payerAcc;

        insert new Payment_Method__c(
            Account__c = payerAcc.Id,
            Card_Type__c = 'VISA'
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/payerAllowedPaymentCards';
        req.httpMethod = 'GET';
        req.params.put('customer_number', '3050');
        req.params.put('company_code', '3000');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PayerAllowedPaymentCardsAPI.getPayerAllowedPaymentCards();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected HTTP 200');
        System.assertNotEquals(null, res.responseBody, 'Expected response body');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        List<Object> paymentCards = (List<Object>) responseMap.get('payment_cards');

        System.assertEquals('S', status.get('message_type'), 'Expected success message type');
        System.assertEquals(1, paymentCards.size(), 'Expected one payment card');

        Map<String, Object> firstCard = (Map<String, Object>) paymentCards[0];
        System.assertEquals('PM', firstCard.get('payment_provider'), 'Expected provider PM');
        System.assertEquals('VISA', firstCard.get('payment_card_type'), 'Expected card type');
        System.assertEquals('Visa', firstCard.get('payment_card_type_ui'), 'Expected UI label');
    }
}