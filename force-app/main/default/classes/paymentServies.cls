@RestResource(urlMapping='/SAPPayment/*')
global with sharing class paymentServies {

    @HttpPost
    global static void processPayment() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        system.debug('req --->' +req);
        system.debug('res --->' +res);
        
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }
        
        try {
            String requestBody = req.requestBody.toString();
            System.debug('Incoming Payment Payload: ' + requestBody);
            
            // Deserialize request body dynamically
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            
            // Extract selectedAccount / payer
            String payer = (String) payload.get('payer');
            if (String.isBlank(payer)) {
                payer = 'Invoice Payer ' + (String) payload.get('selectedAccount');
            }
            
            // Extract invoices list
            List<Object> invoices = (List<Object>) payload.get('invoices');
            Decimal paymentAmount = 0.00;
            String currencyCode = 'USD';
            String targetDocNum = '';
            
            if (invoices != null && !invoices.isEmpty()) {
                Map<String, Object> firstInvoice = (Map<String, Object>) invoices[0];
                currencyCode = (String) firstInvoice.get('currencyKey');
                targetDocNum = (String) firstInvoice.get('billingDocumentNumber');
                
                for (Object invObj : invoices) {
                    Map<String, Object> inv = (Map<String, Object>) invObj;
                    if (inv.get('paymentAmount') != null) {
                        paymentAmount += Decimal.valueOf(String.valueOf(inv.get('paymentAmount')));
                    }
                }
            }
                        
            // Extract paymentMethod details
            Map<String, Object> paymentMethodMap = (Map<String, Object>) payload.get('paymentMethod');
            String token = '';
            String cardLast4 = '';
            String cardType = '';
            String cardholderName = '';
            String validTo = '';
            
            if (paymentMethodMap != null) {
                token = (String) paymentMethodMap.get('token');
                cardLast4 = (String) paymentMethodMap.get('cardLast4Digit');
                cardType = (String) paymentMethodMap.get('cardType');
                cardholderName = (String) paymentMethodMap.get('name');
                validTo = (String) paymentMethodMap.get('validTo');
            }
            
            // Expiry date parsing (e.g. MM-DD-YYYY or MM/YY)
            Integer expiryMonth = 12;
            Integer expiryYear = 2035;
            if (String.isNotBlank(validTo)) {
                List<String> dateParts = validTo.split('-');
                if (dateParts.size() >= 3) {
                    expiryMonth = Integer.valueOf(dateParts[0]);
                    expiryYear = Integer.valueOf(dateParts[2]);
                }
            }
            
            // Perform payment transaction in Salesforce
            String paymentId = executePayment(payer, paymentAmount, currencyCode, token, cardholderName, cardLast4, cardType, expiryMonth, expiryYear);
            if (String.isNotBlank(paymentId) && !paymentId.startsWith('ch_fallback_') && !paymentId.startsWith('cs_fallback_')) {
                updateInvoiceOpenAmounts(payload);
            }
            
            // Update transactionId in cardinalData block
            Map<String, Object> cardinalData = (Map<String, Object>) payload.get('cardinalData');
            if (cardinalData == null) {
                cardinalData = new Map<String, Object>();
                payload.put('cardinalData', cardinalData);
            }
            cardinalData.put('transactionId', paymentId);
            
            // Return updated payload to caller
            res.statusCode = 200;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(payload));
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Invoice Payment Exception: ' + e.getMessage() + '\n' + e.getStackTraceString());
            res.statusCode = 400;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'status' => 'Error',
                'message' => e.getMessage()
            }));
        }
    }
    
    private static void updateInvoiceOpenAmounts(Map<String, Object> payload) {
        List<Object> invoices = (List<Object>) payload.get('invoices');
        if (invoices == null || invoices.isEmpty()) {
            return;
        }

        for (Object invObj : invoices) {
            Map<String, Object> inv = (Map<String, Object>) invObj;
            Decimal openAmount = inv.get('openAmount') != null ? Decimal.valueOf(String.valueOf(inv.get('openAmount'))) : 0.00;
            Decimal paymentAmount = inv.get('paymentAmount') != null ? Decimal.valueOf(String.valueOf(inv.get('paymentAmount'))) : 0.00;

            if (paymentAmount != 0 && openAmount != 0) {
                Decimal updatedOpenAmount = openAmount - paymentAmount;
                // Ensure bounds check (positive open amount shouldn't go below 0; negative open amount shouldn't go above 0)
                if (openAmount > 0 && updatedOpenAmount < 0) {
                    updatedOpenAmount = 0;
                } else if (openAmount < 0 && updatedOpenAmount > 0) {
                    updatedOpenAmount = 0;
                }
                inv.put('openAmount', updatedOpenAmount);
            }
        }
    }
    
    private static String executePayment(
        String payerName, 
        Decimal amount, 
        String currencyCode, 
        String gatewayToken, 
        String cardholderName, 
        String cardLast4, 
        String cardType, 
        Integer expiryMonth, 
        Integer expiryYear
    ) {
        String stripeSessionId = '';
        
        try {
            Integer amounts = (Integer)(amount * 100);

            // Perform callout FIRST before any DML to avoid "uncommitted work pending"
            if (Test.isRunningTest()) {
                stripeSessionId = 'cs_mock_' + String.valueOf(System.currentTimeMillis());
            } else {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(System.Label.Stripe_End_Point);
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                
                String successUrl = 'https://dev-wsap.chronarpay.com/processresponse';
                String cancelUrl = 'https://dev-wsap.chronarpay.com/processresponse';
                String descrip = 'Invoice Payment for ' + payerName;
                
                String body = 'mode=payment'
                    + '&success_url=' + EncodingUtil.urlEncode(successUrl, 'UTF-8')
                    + '&cancel_url=' + EncodingUtil.urlEncode(cancelUrl, 'UTF-8')
                    + '&line_items[0][price_data][currency]=' + (String.isNotBlank(currencyCode) ? currencyCode.toLowerCase() : 'usd')
                    + '&line_items[0][price_data][unit_amount]=' + amounts
                    + '&line_items[0][price_data][product_data][name]=' + EncodingUtil.urlEncode(descrip, 'UTF-8')
                    + '&line_items[0][quantity]=1';
                
                req.setBody(body);
                
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    Map<String, Object> chargeMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    stripeSessionId = (String) chargeMap.get('id');
                } else {
                    throw new AuraHandledException('Stripe Checkout Session creation failed: ' + res.getBody());
                }
            }
            return stripeSessionId;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Stripe transaction failed: ' + e.getMessage());
            return 'cs_fallback_' + String.valueOf(System.currentTimeMillis());
        }
    }
    
    @AuraEnabled
    public static String processPaymentAura(String payloadJson) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestBody = Blob.valueOf(payloadJson);
        RestContext.request = req;
        RestContext.response = res;
        
        processPayment();
        
        return res.responseBody != null ? res.responseBody.toString() : null;
    }
}