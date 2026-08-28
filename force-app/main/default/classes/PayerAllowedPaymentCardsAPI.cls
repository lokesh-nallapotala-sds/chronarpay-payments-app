@RestResource(urlMapping='/payerAllowedPaymentCards/*')
/**
 * Returns the allowed payment cards for a payer account in the CNBS contract shape.
 */
global with sharing class PayerAllowedPaymentCardsAPI {

    /**
     * Handles GET requests for payer allowed payment cards.
     */
    @HttpGet
    global static void getPayerAllowedPaymentCards() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (req == null) {
            req = new RestRequest();
            RestContext.request = req;
        }
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        res.addHeader('Content-Type', 'application/json');

        Map<String, Object> response = new Map<String, Object>();
        try {
            String customerNumber = req.params.get('customer_number');
            String companyCode = req.params.get('company_code');

            validateRequiredParameters(customerNumber, companyCode);

            List<Account> payers = [
                SELECT Id
                FROM Account
                WHERE Type = 'Payer' AND AccountNumber = :customerNumber AND company_code__c = :companyCode
                WITH USER_MODE
                LIMIT 1
            ];

            if (payers.isEmpty()) {
                throw new QueryException('Payer account not found.');
            }

            List<Payment_Method__c> cards = [
                SELECT Id, Card_Type__c
                FROM Payment_Method__c
                WHERE Account__c = :payers[0].Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            response.put('payment_cards', buildPaymentCards(cards));
            response.put('status', buildStatus('S', 10, 'Request successfully processed'));
            res.statusCode = 200;
        } catch (Exception e) {
            response.put('payment_cards', new List<Object>());
            if (e.getMessage().contains('required')) {
                response.put('status', buildStatus('E', 400, e.getMessage()));
                res.statusCode = 400;
            } else if (e.getTypeName() == 'System.QueryException') {
                response.put('status', buildStatus('E', 404, 'Payer account not found.'));
                res.statusCode = 404;
            } else {
                response.put('status', buildStatus('E', 500, e.getMessage()));
                res.statusCode = 500;
            }
        }

        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    private static void validateRequiredParameters(String customerNumber, String companyCode) {
        if (String.isBlank(customerNumber)) {
            throw new CalloutException('customer_number parameter is required.');
        }
        if (String.isBlank(companyCode)) {
            throw new CalloutException('company_code parameter is required.');
        }
    }

    private static List<Map<String, Object>> buildPaymentCards(List<Payment_Method__c> cards) {
        List<Map<String, Object>> paymentCards = new List<Map<String, Object>>();
        if (cards == null || cards.isEmpty()) {
            return paymentCards;
        }

        for (Payment_Method__c card : cards) {
            paymentCards.add(new Map<String, Object>{
                'payment_provider' => 'PM',
                'payment_card_type' => card.Card_Type__c,
                'payment_card_type_ui' => getCardTypeUi(card.Card_Type__c)
            });
        }
        return paymentCards;
    }

    private static Map<String, Object> buildStatus(String messageType, Integer messageNumber, String messageLine) {
        return new Map<String, Object>{
            'message_type' => messageType,
            'message_identification' => '/CNBS/X_API',
            'message_number' => messageNumber,
            'message_line_string' => messageLine
        };
    }

    private static String getCardTypeUi(String cardType) {
        if (String.isBlank(cardType)) {
            return null;
        }

        Map<String, String> uiLabels = new Map<String, String>{
            'AMEX' => 'American Express',
            'EC' => 'eCheck',
            'MC' => 'Master Card',
            'VISA' => 'Visa',
            'DC' => 'Diners Club',
            'DISC' => 'Discover',
            'JCB' => 'JCB'
        };

        return uiLabels.containsKey(cardType) ? uiLabels.get(cardType) : cardType;
    }
}