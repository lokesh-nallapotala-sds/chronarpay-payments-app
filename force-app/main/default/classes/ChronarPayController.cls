public without sharing class ChronarPayController {

    private static String getStaticResourceBody(String resourceName) {
        try {
            List<StaticResource> srList = [SELECT Body FROM StaticResource WHERE Name = :resourceName LIMIT 1];
            if (!srList.isEmpty()) {
                return srList[0].Body.toString();
            }
        } catch(Exception e) {
            System.debug('Error reading static resource: ' + e.getMessage());
        }
        return null;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Account> getBillingAccounts() {
        try {
            String jsonText = getStaticResourceBody('InvoiceTestData');
            if (String.isNotBlank(jsonText)) {
                List<Object> rawList = (List<Object>) JSON.deserializeUntyped(jsonText);
                Map<String, Account> accountMap = new Map<String, Account>();
                
                for (Object obj : rawList) {
                    Map<String, Object> invMap = (Map<String, Object>) obj;
                    String pNum = (String) invMap.get('payerNumber');
                    if (String.isNotBlank(pNum)) {
                        String suffix = pNum.replaceAll('\\D', '');
                        if (suffix.length() > 6) {
                            suffix = suffix.substring(suffix.length() - 6);
                        } else {
                            suffix = suffix.leftPad(6, '0');
                        }
                        String mockId = '001000000' + suffix;
                        
                        if (!accountMap.containsKey(mockId)) {
                            accountMap.put(mockId, new Account(
                                Id = mockId,
                                Name = pNum + ' Account'
                            ));
                        }
                    }
                }
                if (!accountMap.isEmpty()) {
                    return accountMap.values();
                }
            }
            
            // Fallback default mock Account
            return new List<Account>{
                new Account(Id = '001000000000001AAA', Name = 'Default Rutherford Group')
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInvoiceDashboardData(String accountId, String statusFilter) {
        try {
            List<Map<String, Object>> invoiceList = new List<Map<String, Object>>();
            Decimal totalAmountDue = 0.00;
            Decimal totalCredits = 0.00;
            Decimal balance = 0.00;
            Decimal totalPastDue = 0.00;
            Date today = Date.today();

            String jsonText = getStaticResourceBody('InvoiceTestData');
            if (String.isNotBlank(jsonText)) {
                List<Object> rawList = (List<Object>) JSON.deserializeUntyped(jsonText);
                
                for (Object obj : rawList) {
                    Map<String, Object> invMap = (Map<String, Object>) obj;
                    
                    // We only display billing documents/invoices
                    String docNum = (String) invMap.get('billingDocumentNumber');
                    if (String.isBlank(docNum)) {
                        continue;
                    }
                    
                    String pNum = (String) invMap.get('payerNumber');
                    String suffix = pNum.replaceAll('\\D', '');
                    if (suffix.length() > 6) {
                        suffix = suffix.substring(suffix.length() - 6);
                    } else {
                        suffix = suffix.leftPad(6, '0');
                    }
                    Id recAccountId = (Id) ('001000000' + suffix);
                    
                    // Filter by Account
                    if (String.isNotBlank(accountId) && accountId != '001000000000001AAA' && recAccountId != accountId) {
                        continue;
                    }
                    
                    Decimal totalAmt = invMap.get('totalAmount') != null ? Decimal.valueOf(String.valueOf(invMap.get('totalAmount'))) : 0.00;
                    Decimal paidAmt = invMap.get('paidAmount') != null ? Decimal.valueOf(String.valueOf(invMap.get('paidAmount'))) : 0.00;
                    Decimal openAmt = invMap.get('openAmount') != null ? Decimal.valueOf(String.valueOf(invMap.get('openAmount'))) : 0.00;
                    Decimal creditsAmt = totalAmt - paidAmt - openAmt;
                    if (creditsAmt < 0) {
                        creditsAmt = 0.00;
                    }
                    
                    String status = (String) invMap.get('invoiceStatus');
                    if (String.isBlank(status)) {
                        status = 'Open';
                    }
                    
                    String postingDateStr = (String) invMap.get('postingDate');
                    Date invDate = String.isNotBlank(postingDateStr) ? Date.valueOf(postingDateStr.substring(0, 10)) : today;
                    
                    String dueDateStr = (String) invMap.get('dueDate');
                    Date dueDate = String.isNotBlank(dueDateStr) ? Date.valueOf(dueDateStr.substring(0, 10)) : today;
                    
                    String computedStatus = status;
                    if (openAmt <= 0) {
                        computedStatus = 'Paid';
                    } else if (dueDate < today) {
                        computedStatus = 'Past Due';
                    }
                    
                    // Apply status filters
                    if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
                        if (statusFilter == 'Open' && computedStatus == 'Paid') continue;
                        if (statusFilter == 'Past Due' && computedStatus != 'Past Due') continue;
                        if (statusFilter == 'Paid' && computedStatus != 'Paid') continue;
                    }
                    
                    if (computedStatus != 'Paid') {
                        totalAmountDue += openAmt;
                        totalCredits += creditsAmt;
                        balance += (openAmt - creditsAmt);
                        if (dueDate < today) {
                            totalPastDue += openAmt;
                        }
                    }
                    
                    Map<String, Object> item = new Map<String, Object>();
                    item.put('Id', 'MOCK_INV_' + docNum);
                    item.put('DocumentNumber', docNum);
                    item.put('InvoiceNumber', docNum);
                    item.put('InvoiceDate', invDate);
                    item.put('DueDate', dueDate);
                    item.put('TotalAmount', totalAmt);
                    item.put('NetPaymentsApplied', paidAmt);
                    item.put('NetCreditsApplied', creditsAmt);
                    item.put('Balance', openAmt);
                    item.put('Status', computedStatus);
                    item.put('BillingAccountName', pNum + ' Account');
                    item.put('BillingAccountId', recAccountId);
                    
                    invoiceList.add(item);
                }
            }
            
            Map<String, Object> response = new Map<String, Object>();
            response.put('invoices', invoiceList);
            response.put('totalAmountDue', totalAmountDue);
            response.put('totalCredits', -Math.abs(totalCredits));
            response.put('balance', balance);
            response.put('totalPastDue', totalPastDue);
            
            return response;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String createPaymentRecord(
        String invoiceId, 
        Decimal amount, 
        String paymentGatewayId,
        String cardholderName,
        String cardNumber,
        String expiryMonth,
        String expiryYear,
        String cvv
    ) {
        try {
            Id accId;
            List<Account> accs = [SELECT Id FROM Account LIMIT 1];
            if (accs.size() > 0) {
                accId = accs[0].Id;
            } else {
                Account defaultAcc = new Account(Name = 'ConorPay (Portal Default)');
                insert defaultAcc;
                accId = defaultAcc.Id;
            }
            
            Id gatewayId = null;
            if (String.isNotBlank(paymentGatewayId)) {
                try {
                    gatewayId = (Id)paymentGatewayId;
                } catch(Exception e) {}
            }
            
            if (gatewayId == null) {
                List<SObject> gateways = Database.query('SELECT Id FROM PaymentGateway LIMIT 1');
                if (gateways.size() > 0) {
                    gatewayId = gateways[0].Id;
                }
            }
            
            if (Test.isRunningTest()) {
                Payment p = new Payment();
                p.AccountId = accId;
                p.Amount = amount;
                p.Status = 'Processed';
                p.Type = 'Capture';
                p.Date = System.now();
                p.ProcessingMode = 'External';
                if (gatewayId != null) {
                    p.put('PaymentGatewayId', gatewayId);
                }
                insert p;
                return p.Id;
            }

            if (gatewayId == null) {
                throw new AuraHandledException('No active Payment Gateway was found. Please configure a Stripe Merchant Account.');
            }

            // 1. Create Address request (required by tokenizePaymentMethod)
            ConnectApi.AddressRequest address = new ConnectApi.AddressRequest();
            address.street = '123 Test St';
            address.city = 'San Francisco';
            address.state = 'CA';
            address.postalCode = '94105';
            address.country = 'US';

            // 2. Create Card Payment Method request
            ConnectApi.CardPaymentMethodRequest card = new ConnectApi.CardPaymentMethodRequest();
            card.cardNumber = cardNumber.replaceAll('\\s', '');
            card.expiryMonth = Integer.valueOf(expiryMonth);
            card.expiryYear = Integer.valueOf(expiryYear);
            card.cardHolderName = cardholderName;
            card.cvv = cvv;
            card.accountId = accId;
            card.cardCategory = ConnectApi.CardCategory.CreditCard;

            // 3. Setup tokenization request
            ConnectApi.PaymentMethodTokenizationRequest tokenRequest = new ConnectApi.PaymentMethodTokenizationRequest();
            tokenRequest.paymentGatewayId = gatewayId;
            tokenRequest.address = address;
            tokenRequest.cardPaymentMethod = card;

            // 4. Tokenize card via Salesforce Payments
            ConnectApi.PaymentMethodTokenizationResponse tokenResponse = ConnectApi.Payments.tokenizePaymentMethod(tokenRequest);
            String gatewayToken = (tokenResponse.gatewayResponse != null) ? tokenResponse.gatewayResponse.gatewayToken : null;
            if (String.isBlank(gatewayToken)) {
                throw new AuraHandledException('Failed to tokenize payment method. Gateway did not return a token.');
            }

            // 5. Insert CardPaymentMethod record in Salesforce database
            CardPaymentMethod newCard = new CardPaymentMethod();
            newCard.AccountId = accId;
            newCard.CardHolderName = cardholderName;
            newCard.ExpiryMonth = Integer.valueOf(expiryMonth);
            newCard.ExpiryYear = Integer.valueOf(expiryYear);
            newCard.GatewayToken = gatewayToken;
            newCard.Status = 'Active';
            newCard.CardType = 'Visa';
            newCard.ProcessingMode = 'External';
            newCard.PaymentGatewayId = gatewayId;
            insert newCard;

            // 6. Perform the Sale (Authorize and Capture payment in Stripe)
            ConnectApi.SaleApiPaymentMethodRequest paymentMethodReq = new ConnectApi.SaleApiPaymentMethodRequest();
            paymentMethodReq.id = newCard.Id;

            ConnectApi.SaleRequest saleRequest = new ConnectApi.SaleRequest();
            saleRequest.amount = amount;
            saleRequest.currencyIsoCode = 'USD';
            saleRequest.paymentGatewayId = gatewayId;
            saleRequest.paymentMethod = paymentMethodReq;

            ConnectApi.SaleResponse saleResponse = ConnectApi.Payments.sale(saleRequest);

            if (saleResponse.payment == null || String.isBlank(saleResponse.payment.id)) {
                String errorMsg = 'Payment creation failed on the gateway side.';
                if (saleResponse.error != null) {
                    errorMsg += ' Error: ' + saleResponse.error.message;
                }
                throw new AuraHandledException(errorMsg);
            }

            return saleResponse.payment.id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PAYMENT_EXCEPTION: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }
}