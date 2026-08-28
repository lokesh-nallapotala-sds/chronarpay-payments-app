public without sharing class InvoicePaymentController {

    /**
     * Creates an UNCONFIRMED PaymentIntent for Stripe Payment Element.
     * The LWC uses the returned clientSecret with stripe.confirmPayment().
     * Raw card details never pass through Apex.
     */
    @AuraEnabled
    public static String createPaymentIntentForElement(
        String invoicesJson,
        String customerId,
        String currencyCode
    ) {
        try {
            if (String.isBlank(invoicesJson)) {
                throw new AuraHandledException('Invoice data is required.');
            }
            if (String.isBlank(customerId)) {
                throw new AuraHandledException('Select a Stripe customer before paying.');
            }

            if (String.isBlank(currencyCode)) {
                currencyCode = 'usd';
            }
            currencyCode = currencyCode.toLowerCase();

            List<Object> invoices = (List<Object>) JSON.deserializeUntyped(invoicesJson);
            Decimal amount = 0;
            List<String> invoiceNumbers = new List<String>();
            List<String> referenceNumbers = new List<String>();
            String payerNumber = '';

            for (Object obj : invoices) {
                Map<String, Object> inv = (Map<String, Object>) obj;
                Decimal openAmt = inv.get('openAmount') == null
                    ? 0
                    : Decimal.valueOf(String.valueOf(inv.get('openAmount')));
                amount += openAmt;

                String billingDoc = String.valueOf(inv.get('billingDocumentNumber'));
                if (String.isNotBlank(billingDoc) && billingDoc != 'null') {
                    invoiceNumbers.add(billingDoc);
                }

                String refNum = String.valueOf(inv.get('referenceNumber'));
                if (String.isNotBlank(refNum) && refNum != 'null') {
                    referenceNumbers.add(refNum);
                }

                if (inv.containsKey('accountNumber') && inv.get('accountNumber') != null) {
                    payerNumber = String.valueOf(inv.get('accountNumber'));
                }
            }

            Integer cents = (Integer)(amount * 100).round();
            if (cents <= 0) {
                throw new AuraHandledException('Total payment amount must be greater than zero after credits are applied.');
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.stripe.com/v1/payment_intents');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setTimeout(30000);

            String body = 'amount=' + cents
                + '&currency=' + EncodingUtil.urlEncode(currencyCode, 'UTF-8')
                + '&customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8')
                + '&automatic_payment_methods[enabled]=true'
                + '&setup_future_usage=off_session';

            String description = invoiceNumbers.isEmpty()
                ? 'Invoice payment'
                : 'Invoice payment: ' + String.join(invoiceNumbers, ', ');
            if (description.length() > 500) {
                description = description.substring(0, 500);
            }
            body += '&description=' + EncodingUtil.urlEncode(description, 'UTF-8');
            // String invoice = invoiceNumbers.isEmpty()
            //     ? ''
            //     : String.join(invoiceNumbers, ', ');
            // if (invoice.length() > 500) {
            //     invoice = invoice.substring(0, 500);
            // }
            // body += '&invoice=' + EncodingUtil.urlEncode(invoice, 'UTF-8');
            body += '&metadata[billingDocumentNumber]='
                + EncodingUtil.urlEncode(String.join(invoiceNumbers, ','), 'UTF-8')
                + '&metadata[referenceNumber]='
                + EncodingUtil.urlEncode(String.join(referenceNumbers, ','), 'UTF-8')
                + '&metadata[payerNumber]='
                + EncodingUtil.urlEncode(payerNumber, 'UTF-8');

            req.setBody(body);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                throwStripeApiException(res, 'Create PaymentIntent for Payment Element');
            }

            Map<String, Object> paymentIntent =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            Map<String, Object> response = new Map<String, Object>();
            response.put('paymentIntentId', paymentIntent.get('id'));
            response.put('clientSecret', paymentIntent.get('client_secret'));
            response.put('status', paymentIntent.get('status'));
            response.put('amount', paymentIntent.get('amount'));
            response.put('currency', paymentIntent.get('currency'));
            return JSON.serialize(response);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not initialize Stripe Payment Element: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String createPaymentIntent(
        String invoicesJson,
        String customerId,
        String paymentMethodId,
        String paymentMethodToken,
        String cardholderName,
        String currencyCode
    ) {
        try {
            if (String.isBlank(invoicesJson)) {
                throw new AuraHandledException('Invoice data is required.');
            }
            if (String.isBlank(customerId)) {
                throw new AuraHandledException('Select a Stripe customer before paying.');
            }
            if (String.isBlank(paymentMethodId) && String.isBlank(paymentMethodToken)) {
                throw new AuraHandledException('Select an existing payment method or provide a Stripe token for a new payment method.');
            }

            if (String.isBlank(currencyCode)) {
                currencyCode = 'usd';
            }
            currencyCode = currencyCode.toLowerCase();

            List<Object> invoices = (List<Object>) JSON.deserializeUntyped(invoicesJson);
            Decimal amount = 0;
            List<String> invoiceNumbers = new List<String>();
            List<String> referenceNumbers = new List<String>();
            String payerNumber = '';

            for (Object obj : invoices) {
                Map<String, Object> inv = (Map<String, Object>) obj;
                Decimal openAmt = inv.get('openAmount') == null
                    ? 0
                    : Decimal.valueOf(String.valueOf(inv.get('openAmount')));
                amount += openAmt;

                String billingDoc = String.valueOf(inv.get('billingDocumentNumber'));
                if (String.isNotBlank(billingDoc) && billingDoc != 'null') {
                    invoiceNumbers.add(billingDoc);
                }

                String refNum = String.valueOf(inv.get('referenceNumber'));
                if (String.isNotBlank(refNum) && refNum != 'null') {
                    referenceNumbers.add(refNum);
                }

                if (inv.containsKey('accountNumber') && inv.get('accountNumber') != null) {
                    payerNumber = String.valueOf(inv.get('accountNumber'));
                }
            }

            Integer cents = (Integer)(amount * 100).round();
            if (cents <= 0) {
                throw new AuraHandledException('Total payment amount must be greater than zero after credits are applied.');
            }

            // When the user chooses "new payment method", the browser should supply a Stripe token
            // (for example tok_visa in test mode). Raw PAN/CVC values must not be sent through Apex.
            if (String.isBlank(paymentMethodId)) {
                Map<String, Object> customer = retrieveStripeCustomer(customerId);
                String custName = customer != null && customer.get('name') != null ? String.valueOf(customer.get('name')) : '';
                String custEmail = customer != null && customer.get('email') != null ? String.valueOf(customer.get('email')) : '';
                String custPhone = customer != null && customer.get('phone') != null ? String.valueOf(customer.get('phone')) : '';
                Map<String, Object> addressMap = customer != null && customer.get('address') != null ? (Map<String, Object>) customer.get('address') : null;
                String billingName = String.isNotBlank(cardholderName) ? cardholderName.trim() : custName;

                HttpRequest pmReq = new HttpRequest();
                pmReq.setEndpoint('https://api.stripe.com/v1/payment_methods');
                pmReq.setMethod('POST');
                pmReq.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                pmReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                pmReq.setTimeout(30000);

                String pmBody = 'type=card'
                    + '&card[token]=' + EncodingUtil.urlEncode(paymentMethodToken.trim(), 'UTF-8');
                if (String.isNotBlank(billingName)) {
                    pmBody += '&billing_details[name]=' + EncodingUtil.urlEncode(billingName, 'UTF-8');
                }
                if (String.isNotBlank(custEmail)) {
                    pmBody += '&billing_details[email]=' + EncodingUtil.urlEncode(custEmail, 'UTF-8');
                }
                if (String.isNotBlank(custPhone)) {
                    pmBody += '&billing_details[phone]=' + EncodingUtil.urlEncode(custPhone, 'UTF-8');
                }
                if (addressMap != null) {
                    if (addressMap.get('line1') != null && String.isNotBlank(String.valueOf(addressMap.get('line1')))) {
                        pmBody += '&billing_details[address][line1]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('line1')), 'UTF-8');
                    }
                    if (addressMap.get('line2') != null && String.isNotBlank(String.valueOf(addressMap.get('line2')))) {
                        pmBody += '&billing_details[address][line2]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('line2')), 'UTF-8');
                    }
                    if (addressMap.get('city') != null && String.isNotBlank(String.valueOf(addressMap.get('city')))) {
                        pmBody += '&billing_details[address][city]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('city')), 'UTF-8');
                    }
                    if (addressMap.get('state') != null && String.isNotBlank(String.valueOf(addressMap.get('state')))) {
                        pmBody += '&billing_details[address][state]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('state')), 'UTF-8');
                    }
                    if (addressMap.get('postal_code') != null && String.isNotBlank(String.valueOf(addressMap.get('postal_code')))) {
                        pmBody += '&billing_details[address][postal_code]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('postal_code')), 'UTF-8');
                    }
                    if (addressMap.get('country') != null && String.isNotBlank(String.valueOf(addressMap.get('country')))) {
                        pmBody += '&billing_details[address][country]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('country')), 'UTF-8');
                    }
                }
                pmBody += '&metadata[customer_id]=' + EncodingUtil.urlEncode(customerId, 'UTF-8');
                if (String.isNotBlank(custName)) {
                    pmBody += '&metadata[customer_name]=' + EncodingUtil.urlEncode(custName, 'UTF-8');
                }
                if (String.isNotBlank(custEmail)) {
                    pmBody += '&metadata[customer_email]=' + EncodingUtil.urlEncode(custEmail, 'UTF-8');
                }

                pmReq.setBody(pmBody);

                HttpResponse pmRes = new Http().send(pmReq);
                if (pmRes.getStatusCode() < 200 || pmRes.getStatusCode() >= 300) {
                    throwStripeApiException(pmRes, 'Create payment method');
                }

                Map<String, Object> pmResponse = (Map<String, Object>) JSON.deserializeUntyped(pmRes.getBody());
                paymentMethodId = (String) pmResponse.get('id');
                if (String.isBlank(paymentMethodId)) {
                    throw new AuraHandledException('Stripe did not return a payment method ID.');
                }
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.stripe.com/v1/payment_intents');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setTimeout(30000);

            String body = 'amount=' + cents
                + '&currency=' + EncodingUtil.urlEncode(currencyCode, 'UTF-8')
                + '&customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8')
                + '&payment_method=' + EncodingUtil.urlEncode(paymentMethodId, 'UTF-8')
                + '&payment_method_types[0]=card'
                + '&confirm=true'
                + '&setup_future_usage=off_session'
                + '&error_on_requires_action=true';

            String description = invoiceNumbers.isEmpty()
                ? 'Invoice payment'
                : 'Invoice payment: ' + String.join(invoiceNumbers, ', ');
            if (description.length() > 500) {
                description = description.substring(0, 500);
            }
            body += '&description=' + EncodingUtil.urlEncode(description, 'UTF-8');

            // String invoice = invoiceNumbers.isEmpty()
            //     ? ''
            //     : String.join(invoiceNumbers, ', ');
            // if (invoice.length() > 500) {
            //     invoice = invoice.substring(0, 500);
            // }
            // body += '&invoice=' + EncodingUtil.urlEncode(invoice, 'UTF-8');

            body += '&metadata[billingDocumentNumber]='
                + EncodingUtil.urlEncode(String.join(invoiceNumbers, ','), 'UTF-8')
                + '&metadata[referenceNumber]='
                + EncodingUtil.urlEncode(String.join(referenceNumbers, ','), 'UTF-8')
                + '&metadata[payerNumber]='
                + EncodingUtil.urlEncode(payerNumber, 'UTF-8');

            req.setBody(body);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                throwStripeApiException(res, 'Create/confirm PaymentIntent');
            }

            Map<String, Object> paymentIntent = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String status = (String) paymentIntent.get('status');

            Map<String, Object> response = new Map<String, Object>();
            response.put('paymentIntentId', paymentIntent.get('id'));
            response.put('paymentMethodId', paymentIntent.get('payment_method'));
            response.put('status', status);
            response.put('amount', paymentIntent.get('amount'));
            response.put('currency', paymentIntent.get('currency'));

            if (status != 'succeeded') {
                response.put('message', 'Stripe returned PaymentIntent status: ' + status);
            }

            return JSON.serialize(response);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not process Stripe payment: ' + e.getMessage());
        }
    }
    /**
     * List recent Stripe Charges (both succeeded and failed).
     * Returns the raw Stripe JSON response as a String so the LWC
     * can parse and display the transactions.
     *
     * @param limit  Maximum number of charges to retrieve (max 100)
     */
    @AuraEnabled
    public static String listCharges(Integer limitUsed, String customerId) {
        try {
            if (limitUsed == null) limitUsed = 50;
            if (limitUsed < 1) limitUsed = 1;
            if (limitUsed > 100) limitUsed = 100;

            String endpoint = 'https://api.stripe.com/v1/charges?limit=' + limitUsed;
            if (String.isNotBlank(customerId)) {
                endpoint += '&customer=' + EncodingUtil.urlEncode(customerId.trim(), 'UTF-8');
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return res.getBody();
            }

            // Try to extract Stripe error message
            try {
                Map<String, Object> errResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> error = (Map<String, Object>) errResp.get('error');
                String errMsg = error != null ? (String) error.get('message') : 'Stripe API error';
                throw new AuraHandledException('Stripe listCharges error: ' + errMsg);
            } catch (Exception ex) {
                throw new AuraHandledException('Stripe listCharges failed with status: ' + res.getStatusCode());
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not list charges: ' + e.getMessage());
        }
    }
    /**
     * Checks if a Stripe Customer exists for the given Salesforce Account ID.
     * If found, retrieves that customer and their payment methods.
     * If not found, automatically provisions a new customer in Stripe with the Account info
     * and returns the new customer details and empty payment methods list.
     * Also syncs payment methods to Salesforce Payment_Method__c records.
     */
    @AuraEnabled
    public static String getOrCreateCustomerAndPaymentMethods(Id accountId) {
        try {
            if (accountId == null) {
                throw new AuraHandledException('Account ID is required.');
            }

            // 1. Retrieve Account details from Salesforce
            List<Account> accList = [
                SELECT Id, Name, AccountNumber, Phone, Sales_Organization__c,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
            if (accList.isEmpty()) {
                throw new AuraHandledException('Salesforce Account not found for Id: ' + accountId);
            }
            Account acc = accList[0];

            // Primary contact email if available
            List<Contact> contacts = [
                SELECT Id, Email, Name, Phone
                FROM Contact
                WHERE AccountId = :accountId AND Email != null
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            String contactEmail = !contacts.isEmpty() ? contacts[0].Email : '';

            // 2. Search for existing Stripe customer
            Map<String, Object> stripeCustomer = findStripeCustomerForAccount(acc, contactEmail);
            Boolean isNewCustomer = false;

            if (stripeCustomer == null) {
                // 3. Create new customer in Stripe
                stripeCustomer = createStripeCustomerForAccount(acc, contactEmail);
                isNewCustomer = true;
            } else {
                // Ensure customer metadata is linked with Salesforce Account if missing
                ensureCustomerMetadata(stripeCustomer, acc);
            }

            String customerId = (String) stripeCustomer.get('id');

            // 4. Retrieve payment methods for this specific customer
            List<Object> paymentMethods = retrieveCustomerPaymentMethodsList(customerId);

            // NOTE: Cards are NOT synced to Payment_Method__c here.
            // Sync happens only after a successful Stripe payment via syncPaymentCards().

            Map<String, Object> result = new Map<String, Object>();
            result.put('customer', stripeCustomer);
            result.put('isNewCustomer', isNewCustomer);
            result.put('paymentMethods', paymentMethods);
            result.put('accountId', acc.Id);
            result.put('accountName', acc.Name);
            result.put('accountNumber', acc.AccountNumber);
            result.put('salesOrganization', acc.Sales_Organization__c);
            result.put('email', contactEmail);
            result.put('phone', String.isNotBlank(acc.Phone) ? acc.Phone : (!contacts.isEmpty() && String.isNotBlank(contacts[0].Phone) ? contacts[0].Phone : ''));
            result.put('billingStreet', acc.BillingStreet != null ? acc.BillingStreet : '');
            result.put('billingCity', acc.BillingCity != null ? acc.BillingCity : '');
            result.put('billingState', acc.BillingState != null ? acc.BillingState : '');
            result.put('billingPostalCode', acc.BillingPostalCode != null ? acc.BillingPostalCode : '');
            result.put('billingCountry', acc.BillingCountry != null ? acc.BillingCountry : '');

            return JSON.serialize(result);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to process Stripe customer: ' + e.getMessage());
        }
    }

    /**
     * Retrieves all saved payment methods for a specific Stripe customer.
     */
    @AuraEnabled
    public static String getCustomerPaymentMethods(String customerId) {
        try {
            if (String.isBlank(customerId)) {
                throw new AuraHandledException('Customer ID is required.');
            }
            List<Object> paymentMethods = retrieveCustomerPaymentMethodsList(customerId);
            Map<String, Object> response = new Map<String, Object>();
            response.put('data', paymentMethods);
            response.put('total_count', paymentMethods.size());
            return JSON.serialize(response);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not list customer payment methods: ' + e.getMessage());
        }
    }

    /**
     * Syncs Stripe payment methods to Salesforce Payment_Method__c after a successful payment.
     * Call this from LWC once Stripe confirms the payment succeeded.
     * This ensures cards are only recorded in SF after real payment activity.
     *
     * @param accountId   Salesforce Account Id (the payer)
     * @param customerId  Stripe Customer Id
     */
    @AuraEnabled
    public static void syncPaymentCards(Id accountId, String customerId) {
        try {
            if (accountId == null || String.isBlank(customerId)) {
                return;
            }
            List<Object> paymentMethods = retrieveCustomerPaymentMethodsList(customerId);
            syncPaymentCardsToSalesforce(accountId, customerId, paymentMethods);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            // Non-fatal: log but don't block the user's success flow
            System.debug('syncPaymentCards error: ' + e.getMessage());
        }
    }

    /**
     * Records or updates a Stripe payment transaction in the Salesforce Payment__c custom object.
     * Handles both successful and failed/canceled payment attempts.
     * Links the Payment__c record to the Account__c and Payment_Method__c (if matching card exists).
     *
     * @param accountId         Salesforce Account Id (payer)
     * @param amount            Payment amount in standard currency units (e.g. 150.00)
     * @param amountReceived    Amount received in standard currency units (e.g. 150.00 for Paid, 0 for Failed)
     * @param currencyCode      Currency code (e.g. 'USD')
     * @param paymentIntentId   Stripe PaymentIntent ID (e.g. 'pi_xxx')
     * @param paymentMethodId   Stripe PaymentMethod ID (e.g. 'pm_xxx')
     * @param status            Payment status ('Paid', 'Failed', 'Processing', 'Canceled', 'Pending')
     * @param failureReason     Failure or decline reason if payment failed (truncated to max 255 chars)
     * @return                  Id of the created or updated Payment__c record
     */
    @AuraEnabled
    public static Id recordPayment(
        Id accountId,
        Decimal amount,
        Decimal amountReceived,
        String currencyCode,
        String paymentIntentId,
        String paymentMethodId,
        String status,
        String failureReason
    ) {
        try {
            if (accountId == null) {
                System.debug('recordPayment: accountId is required for Payment__c MasterDetail.');
                return null;
            }

            // Normalize status to valid picklist values on Payment__c.Status__c:
            // 'Pending', 'Processing', 'Paid', 'Failed', 'Canceled', 'Refunded', 'Partially Refunded'
            String normalizedStatus = 'Pending';
            if (String.isNotBlank(status)) {
                String s = status.trim().toLowerCase();
                if (s == 'succeeded' || s == 'paid' || s == 'complete' || s == 'completed') {
                    normalizedStatus = 'Paid';
                } else if (s == 'failed' || s == 'declined' || s == 'error' || s == 'requires_payment_method' || s == 'requires_action') {
                    normalizedStatus = 'Failed';
                } else if (s == 'processing') {
                    normalizedStatus = 'Processing';
                } else if (s == 'canceled' || s == 'cancelled') {
                    normalizedStatus = 'Canceled';
                } else if (s == 'refunded') {
                    normalizedStatus = 'Refunded';
                } else if (s == 'partially refunded' || s == 'partially_refunded') {
                    normalizedStatus = 'Partially Refunded';
                } else {
                    normalizedStatus = 'Pending';
                }
            }

            // Normalize currency
            String normalizedCurrency = String.isNotBlank(currencyCode) ? currencyCode.trim().toUpperCase() : 'USD';
            if (normalizedCurrency.length() > 3) {
                normalizedCurrency = normalizedCurrency.substring(0, 3);
            }

            // Truncate failure reason if necessary
            String truncatedFailure = '';
            if (String.isNotBlank(failureReason)) {
                truncatedFailure = failureReason.trim();
                if (truncatedFailure.length() > 255) {
                    truncatedFailure = truncatedFailure.substring(0, 255);
                }
            }

            // Lookup or create matching Payment_Method__c if paymentMethodId provided
            Id sfPaymentMethodId = null;
            if (String.isNotBlank(paymentMethodId)) {
                List<Payment_Method__c> pms = [
                    SELECT Id
                    FROM Payment_Method__c
                    WHERE Card_Token__c = :paymentMethodId.trim()
                    LIMIT 1
                ];
                if (!pms.isEmpty()) {
                    sfPaymentMethodId = pms[0].Id;
                } else {
                    // First create the SF Payment_Method__c record directly from Stripe details
                    sfPaymentMethodId = createPaymentMethodFromStripe(accountId, paymentMethodId.trim());
                }
            }

            // Fallback: If sfPaymentMethodId is still null, link the latest payment method for this account if any
            if (sfPaymentMethodId == null && accountId != null) {
                List<Payment_Method__c> latestPm = [
                    SELECT Id
                    FROM Payment_Method__c
                    WHERE Account__c = :accountId
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!latestPm.isEmpty()) {
                    sfPaymentMethodId = latestPm[0].Id;
                }
            }

            // Check for existing Payment__c with the same Stripe PaymentIntent ID for idempotency
            Payment__c paymentRecord = null;
            if (String.isNotBlank(paymentIntentId)) {
                List<Payment__c> existingList = [
                    SELECT Id, Status__c, Amount__c, Amount_Received__c, Failure_Reason__c, Payment_Method__c
                    FROM Payment__c
                    WHERE Payment_Intent_Id__c = :paymentIntentId.trim()
                    LIMIT 1
                ];
                if (!existingList.isEmpty()) {
                    paymentRecord = existingList[0];
                }
            }

            if (paymentRecord != null) {
                paymentRecord.Status__c = normalizedStatus;
                if (amount != null) {
                    paymentRecord.Amount__c = amount;
                }
                if (amountReceived != null) {
                    paymentRecord.Amount_Received__c = amountReceived;
                } else if (normalizedStatus == 'Paid' && amount != null) {
                    paymentRecord.Amount_Received__c = amount;
                }
                if (String.isNotBlank(truncatedFailure)) {
                    paymentRecord.Failure_Reason__c = truncatedFailure;
                }
                if (sfPaymentMethodId != null) {
                    paymentRecord.Payment_Method__c = sfPaymentMethodId;
                }
                update paymentRecord;
                return paymentRecord.Id;
            } else {
                paymentRecord = new Payment__c();
                paymentRecord.Account__c = accountId;
                paymentRecord.Amount__c = amount != null ? amount : 0;
                paymentRecord.Amount_Received__c = amountReceived != null
                    ? amountReceived
                    : (normalizedStatus == 'Paid' && amount != null ? amount : 0);
                paymentRecord.Amount_Refunded__c = 0;
                paymentRecord.Currency__c = normalizedCurrency;
                paymentRecord.Payment_Date__c = System.now();
                paymentRecord.Status__c = normalizedStatus;
                paymentRecord.Payment_Intent_Id__c = String.isNotBlank(paymentIntentId) ? paymentIntentId.trim() : null;
                paymentRecord.Failure_Reason__c = String.isNotBlank(truncatedFailure) ? truncatedFailure : null;
                paymentRecord.Payment_Method__c = sfPaymentMethodId;

                insert paymentRecord;
                return paymentRecord.Id;
            }
        } catch (Exception e) {
            System.debug('recordPayment error: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Retrieves a single PaymentMethod from Stripe by its pm_xxx ID and creates a Payment_Method__c record in SF if not already present.
     */
    public static Id createPaymentMethodFromStripe(Id accountId, String paymentMethodId) {
        if (accountId == null || String.isBlank(paymentMethodId)) {
            return null;
        }

        try {
            // First check if it already exists
            List<Payment_Method__c> existing = [
                SELECT Id
                FROM Payment_Method__c
                WHERE Card_Token__c = :paymentMethodId.trim()
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }

            // Call Stripe to get payment method details
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.stripe.com/v1/payment_methods/' + EncodingUtil.urlEncode(paymentMethodId.trim(), 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> pm = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> pmList = new List<Object>{ pm };
                syncPaymentCardsToSalesforce(accountId, null, pmList);

                List<Payment_Method__c> newlyCreated = [
                    SELECT Id
                    FROM Payment_Method__c
                    WHERE Card_Token__c = :paymentMethodId.trim()
                    LIMIT 1
                ];
                if (!newlyCreated.isEmpty()) {
                    return newlyCreated[0].Id;
                }
            }
        } catch (Exception e) {
            System.debug('createPaymentMethodFromStripe error: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Searches Stripe for a customer matching the Salesforce Account.
     * Matches by:
     * 1) metadata['salesforce_account_id']
     * 2) metadata['account_number']
     * 3) customer Name
     * 4) customer Description
     * 5) customer Email (if Contact email present)
     */
    private static Map<String, Object> findStripeCustomerForAccount(Account acc, String contactEmail) {
        try {
            String nextUrl = 'https://api.stripe.com/v1/customers?limit=100';
            String accIdStr = String.valueOf(acc.Id);
            String accNumStr = String.isNotBlank(acc.AccountNumber) ? acc.AccountNumber.trim() : '';
            String accSalesOrgStr = String.isNotBlank(acc.Sales_Organization__c) ? acc.Sales_Organization__c.trim() : '';
            String accNameStr = String.isNotBlank(acc.Name) ? acc.Name.trim() : '';
            String emailStr = String.isNotBlank(contactEmail) ? contactEmail.trim() : '';

            while (String.isNotBlank(nextUrl)) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(nextUrl);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                req.setTimeout(30000);

                HttpResponse res = new Http().send(req);
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    break;
                }

                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> data = (List<Object>) root.get('data');
                if (data == null || data.isEmpty()) {
                    break;
                }

                for (Object item : data) {
                    Map<String, Object> cust = (Map<String, Object>) item;
                    Map<String, Object> meta = cust.containsKey('metadata') && cust.get('metadata') != null
                        ? (Map<String, Object>) cust.get('metadata')
                        : new Map<String, Object>();

                    String sfAccIdMeta = meta.containsKey('salesforce_account_id') && meta.get('salesforce_account_id') != null
                        ? String.valueOf(meta.get('salesforce_account_id')).trim() : '';
                    String accNumMeta = meta.containsKey('account_number') && meta.get('account_number') != null
                        ? String.valueOf(meta.get('account_number')).trim() : '';
                    String salesOrgMeta = meta.containsKey('sales_organization') && meta.get('sales_organization') != null
                        ? String.valueOf(meta.get('sales_organization')).trim() : '';

                    // 1. Exact Salesforce Account ID Match (Highest Priority)
                    if (String.isNotBlank(sfAccIdMeta) && sfAccIdMeta == accIdStr) {
                        return cust;
                    }

                    // If this customer is explicitly tied to a DIFFERENT Salesforce Account ID, DO NOT match it
                    if (String.isNotBlank(sfAccIdMeta) && sfAccIdMeta != accIdStr) {
                        continue;
                    }

                    // If both this account and metadata have sales_org specified, but they DO NOT match, DO NOT match it
                    if (String.isNotBlank(accSalesOrgStr) && String.isNotBlank(salesOrgMeta) && !salesOrgMeta.equalsIgnoreCase(accSalesOrgStr)) {
                        continue;
                    }

                    // 2. Exact Account Number + Sales Org Match
                    if (String.isNotBlank(accNumStr) && String.isNotBlank(accNumMeta) && accNumMeta.equalsIgnoreCase(accNumStr)) {
                        if (String.isNotBlank(accSalesOrgStr) && String.isNotBlank(salesOrgMeta) && salesOrgMeta.equalsIgnoreCase(accSalesOrgStr)) {
                            return cust;
                        }
                        if (String.isBlank(accSalesOrgStr) && String.isBlank(salesOrgMeta)) {
                            return cust;
                        }
                    }

                    // 3. Check description match considering both account number and sales org
                    String cDesc = cust.containsKey('description') && cust.get('description') != null
                        ? String.valueOf(cust.get('description')).trim() : '';
                    if (String.isNotBlank(cDesc)) {
                        if (String.isNotBlank(accNumStr) && cDesc.containsIgnoreCase(accNumStr)) {
                            if (String.isNotBlank(accSalesOrgStr) && cDesc.containsIgnoreCase(accSalesOrgStr)) {
                                return cust;
                            }
                        }
                    }
                }

                Boolean hasMore = root.get('has_more') != null ? Boolean.valueOf(root.get('has_more')) : false;
                if (!hasMore) {
                    break;
                }

                Map<String, Object> lastItem = (Map<String, Object>) data[data.size() - 1];
                String lastId = (String) lastItem.get('id');
                if (String.isBlank(lastId)) {
                    break;
                }

                nextUrl = 'https://api.stripe.com/v1/customers?limit=100&starting_after='
                    + EncodingUtil.urlEncode(lastId, 'UTF-8');
            }
        } catch (Exception e) {
            System.debug('findStripeCustomerForAccount error: ' + e.getMessage());
        }
        return null;
    }

    /**
     * Creates a new customer in Stripe using the Salesforce Account details.
     */
    private static Map<String, Object> createStripeCustomerForAccount(Account acc, String contactEmail) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.stripe.com/v1/customers');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(30000);

        String body = 'name=' + EncodingUtil.urlEncode(acc.Name, 'UTF-8');

        String descStr = acc.Name;
        if (String.isNotBlank(acc.AccountNumber)) {
            descStr += ' - ' + acc.AccountNumber.trim();
        }
        if (String.isNotBlank(acc.Sales_Organization__c)) {
            descStr += ' (' + acc.Sales_Organization__c.trim() + ')';
        }
        body += '&description=' + EncodingUtil.urlEncode(descStr, 'UTF-8');

        if (String.isNotBlank(contactEmail)) {
            body += '&email=' + EncodingUtil.urlEncode(contactEmail.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.Phone)) {
            body += '&phone=' + EncodingUtil.urlEncode(acc.Phone.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.BillingStreet)) {
            body += '&address[line1]=' + EncodingUtil.urlEncode(acc.BillingStreet.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.BillingCity)) {
            body += '&address[city]=' + EncodingUtil.urlEncode(acc.BillingCity.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.BillingState)) {
            body += '&address[state]=' + EncodingUtil.urlEncode(acc.BillingState.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.BillingPostalCode)) {
            body += '&address[postal_code]=' + EncodingUtil.urlEncode(acc.BillingPostalCode.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.BillingCountry)) {
            body += '&address[country]=' + EncodingUtil.urlEncode(acc.BillingCountry.trim(), 'UTF-8');
        }

        body += '&metadata[salesforce_account_id]=' + EncodingUtil.urlEncode(String.valueOf(acc.Id), 'UTF-8');
        if (String.isNotBlank(acc.AccountNumber)) {
            body += '&metadata[account_number]=' + EncodingUtil.urlEncode(acc.AccountNumber.trim(), 'UTF-8');
        }
        if (String.isNotBlank(acc.Sales_Organization__c)) {
            body += '&metadata[sales_organization]=' + EncodingUtil.urlEncode(acc.Sales_Organization__c.trim(), 'UTF-8');
        }

        req.setBody(body);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throwStripeApiException(res, 'Create customer in Stripe');
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Updates Stripe customer metadata if salesforce_account_id or sales_organization is not already present.
     */
    private static void ensureCustomerMetadata(Map<String, Object> stripeCustomer, Account acc) {
        try {
            if (stripeCustomer == null || !stripeCustomer.containsKey('id')) return;
            String customerId = (String) stripeCustomer.get('id');
            Map<String, Object> meta = stripeCustomer.containsKey('metadata') && stripeCustomer.get('metadata') != null
                ? (Map<String, Object>) stripeCustomer.get('metadata')
                : new Map<String, Object>();

            Boolean needUpdate = false;
            String body = '';

            if (!meta.containsKey('salesforce_account_id') || String.isBlank(String.valueOf(meta.get('salesforce_account_id')))) {
                body += 'metadata[salesforce_account_id]=' + EncodingUtil.urlEncode(String.valueOf(acc.Id), 'UTF-8');
                needUpdate = true;
            }
            if (String.isNotBlank(acc.AccountNumber) && (!meta.containsKey('account_number') || String.isBlank(String.valueOf(meta.get('account_number'))))) {
                if (String.isNotBlank(body)) body += '&';
                body += 'metadata[account_number]=' + EncodingUtil.urlEncode(acc.AccountNumber.trim(), 'UTF-8');
                needUpdate = true;
            }
            if (String.isNotBlank(acc.Sales_Organization__c) && (!meta.containsKey('sales_organization') || String.isBlank(String.valueOf(meta.get('sales_organization'))))) {
                if (String.isNotBlank(body)) body += '&';
                body += 'metadata[sales_organization]=' + EncodingUtil.urlEncode(acc.Sales_Organization__c.trim(), 'UTF-8');
                needUpdate = true;
            }

            if (needUpdate) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint('https://api.stripe.com/v1/customers/' + EncodingUtil.urlEncode(customerId, 'UTF-8'));
                req.setMethod('POST');
                req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                req.setTimeout(15000);
                req.setBody(body);
                new Http().send(req);
            }
        } catch (Exception e) {
            System.debug('ensureCustomerMetadata error: ' + e.getMessage());
        }
    }

    /**
     * Retrieves card payment methods for a specific Stripe customer.
     */
    private static List<Object> retrieveCustomerPaymentMethodsList(String customerId) {
        List<Object> allMethods = new List<Object>();
        if (String.isBlank(customerId)) {
            return allMethods;
        }

        String nextUrl = 'https://api.stripe.com/v1/payment_methods?customer='
            + EncodingUtil.urlEncode(customerId.trim(), 'UTF-8') + '&type=card&limit=100';

        while (String.isNotBlank(nextUrl)) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(nextUrl);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                break;
            }

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> data = (List<Object>) root.get('data');
            if (data != null) {
                allMethods.addAll(data);
            }

            Boolean hasMore = root.get('has_more') != null ? Boolean.valueOf(root.get('has_more')) : false;
            if (!hasMore || data == null || data.isEmpty()) {
                break;
            }

            Map<String, Object> lastItem = (Map<String, Object>) data[data.size() - 1];
            String lastId = (String) lastItem.get('id');
            if (String.isBlank(lastId)) {
                break;
            }

            nextUrl = 'https://api.stripe.com/v1/payment_methods?customer='
                + EncodingUtil.urlEncode(customerId.trim(), 'UTF-8') + '&type=card&limit=100&starting_after='
                + EncodingUtil.urlEncode(lastId, 'UTF-8');
        }
        return allMethods;
    }

    /**
     * Synchronizes Stripe payment methods to Salesforce Payment_Method__c records for this Account.
     */
    private static void syncPaymentCardsToSalesforce(Id accountId, String customerId, List<Object> paymentMethods) {
        if (accountId == null || paymentMethods == null || paymentMethods.isEmpty()) {
            return;
        }

        try {
            Set<String> pmIds = new Set<String>();
            for (Object obj : paymentMethods) {
                if (obj instanceof Map<String, Object>) {
                    Map<String, Object> pm = (Map<String, Object>) obj;
                    String pmId = (String) pm.get('id');
                    if (String.isNotBlank(pmId)) {
                        pmIds.add(pmId.trim());
                    }
                }
            }
            if (pmIds.isEmpty()) {
                return;
            }

            // Find existing Payment_Method__c for this Account or matching Card_Token__c
            List<Payment_Method__c> existingCards = [
                SELECT Id, Card_Token__c, Last_Four__c, Card_Type__c, Cardholder_Name__c, Account__c
                FROM Payment_Method__c
                WHERE Account__c = :accountId OR Card_Token__c IN :pmIds
            ];

            Set<String> existingTokens = new Set<String>();
            for (Payment_Method__c pc : existingCards) {
                if (String.isNotBlank(pc.Card_Token__c)) {
                    existingTokens.add(pc.Card_Token__c.trim());
                }
            }

            List<Payment_Method__c> cardsToInsert = new List<Payment_Method__c>();
            Set<String> queuedTokens = new Set<String>();

            String defaultCardholderName = '';
            List<Account> aList = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
            if (!aList.isEmpty()) {
                defaultCardholderName = aList[0].Name;
            }

            for (Object obj : paymentMethods) {
                if (!(obj instanceof Map<String, Object>)) continue;
                Map<String, Object> pm = (Map<String, Object>) obj;
                String pmId = (String) pm.get('id');
                if (String.isBlank(pmId)) continue;
                pmId = pmId.trim();

                // Prevent duplicates
                if (existingTokens.contains(pmId) || queuedTokens.contains(pmId)) {
                    continue;
                }

                Map<String, Object> card = pm.containsKey('card') && pm.get('card') != null
                    ? (Map<String, Object>) pm.get('card')
                    : new Map<String, Object>();
                Map<String, Object> billing = pm.containsKey('billing_details') && pm.get('billing_details') != null
                    ? (Map<String, Object>) pm.get('billing_details')
                    : new Map<String, Object>();

                String brand = card.containsKey('brand') && card.get('brand') != null
                    ? String.valueOf(card.get('brand')) : '';
                String last4 = card.containsKey('last4') && card.get('last4') != null
                    ? String.valueOf(card.get('last4')) : '';
                Integer expMonth = card.containsKey('exp_month') && card.get('exp_month') != null
                    ? Integer.valueOf(card.get('exp_month')) : 12;
                Integer expYear = card.containsKey('exp_year') && card.get('exp_year') != null
                    ? Integer.valueOf(card.get('exp_year')) : 2030;
                String cardholderName = billing.containsKey('name') && billing.get('name') != null
                    ? String.valueOf(billing.get('name')) : '';
                if (String.isBlank(cardholderName)) {
                    cardholderName = defaultCardholderName;
                }

                Payment_Method__c newCard = new Payment_Method__c();
                newCard.Account__c = accountId;
                newCard.Card_Token__c = pmId;
                newCard.Card_Type__c = normalizeCardBrand(brand);
                newCard.Last_Four__c = last4;
                newCard.Cardholder_Name__c = cardholderName;
                newCard.Valid_To__c = Date.newInstance(expYear, expMonth, 1);
                newCard.Is_Default__c = (existingCards.isEmpty() && cardsToInsert.isEmpty());

                cardsToInsert.add(newCard);
                queuedTokens.add(pmId);
            }

            if (!cardsToInsert.isEmpty()) {
                insert cardsToInsert;
            }
        } catch (Exception e) {
            System.debug('syncPaymentCardsToSalesforce error: ' + e.getMessage());
        }
    }

    /**
     * Normalizes Stripe card brand to valid picklist values on Payment_Method__c.Card_Type__c.
     */
    private static String normalizeCardBrand(String brand) {
        if (String.isBlank(brand)) return 'VISA';
        String b = brand.trim().toLowerCase();
        if (b == 'visa') return 'VISA';
        if (b == 'mastercard') return 'Mastercard';
        if (b == 'amex' || b == 'american express') return 'AMEX';
        if (b == 'discover') return 'Discover';
        return 'VISA';
    }

    @AuraEnabled
    public static String listCustomers(Integer limitUsed) {
        try {
            if (limitUsed == null) limitUsed = 100;
            if (limitUsed < 1) limitUsed = 1;
            if (limitUsed > 100) limitUsed = 100;

            List<Object> allCustomers = new List<Object>();
            String nextUrl = 'https://api.stripe.com/v1/customers?limit=' + limitUsed;

            while (String.isNotBlank(nextUrl)) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(nextUrl);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                req.setTimeout(30000);

                HttpResponse res = new Http().send(req);
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    throwStripeApiException(res, 'List customers');
                    return null;
                }

                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> data = (List<Object>) root.get('data');
                if (data != null) {
                    allCustomers.addAll(data);
                }

                Boolean hasMore = root.get('has_more') != null ? Boolean.valueOf(root.get('has_more')) : false;
                if (!hasMore || data == null || data.isEmpty()) {
                    break;
                }

                Map<String, Object> lastItem = (Map<String, Object>) data[data.size() - 1];
                String lastId = (String) lastItem.get('id');
                if (String.isBlank(lastId)) {
                    break;
                }

                nextUrl = 'https://api.stripe.com/v1/customers?limit=' + limitUsed
                    + '&starting_after=' + EncodingUtil.urlEncode(lastId, 'UTF-8');
            }

            Map<String, Object> response = new Map<String, Object>();
            response.put('data', allCustomers);
            response.put('has_more', false);
            response.put('total_count', allCustomers.size());
            return JSON.serialize(response);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not list customers: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String createPaymentMethodForCustomer(String customerId, String cardholderName, String paymentMethodToken) {
        try {
            if (String.isBlank(customerId)) {
                throw new AuraHandledException('Customer ID is required.');
            }

            if (String.isBlank(paymentMethodToken)) {
                throw new AuraHandledException('A Stripe card token is required (e.g. tok_visa).');
            }

            // Retrieve customer details from Stripe to capture name, email, phone, address, and metadata
            Map<String, Object> customer = retrieveStripeCustomer(customerId);
            String custName = customer != null && customer.get('name') != null ? String.valueOf(customer.get('name')) : '';
            String custEmail = customer != null && customer.get('email') != null ? String.valueOf(customer.get('email')) : '';
            String custPhone = customer != null && customer.get('phone') != null ? String.valueOf(customer.get('phone')) : '';
            Map<String, Object> addressMap = customer != null && customer.get('address') != null ? (Map<String, Object>) customer.get('address') : null;
            Map<String, Object> metadataMap = customer != null && customer.get('metadata') != null ? (Map<String, Object>) customer.get('metadata') : null;

            String billingName = String.isNotBlank(cardholderName) ? cardholderName.trim() : custName;

            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.stripe.com/v1/payment_methods');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setTimeout(30000);

            String body = 'type=card'
                + '&card[token]=' + EncodingUtil.urlEncode(paymentMethodToken.trim(), 'UTF-8');

            if (String.isNotBlank(billingName)) {
                body += '&billing_details[name]=' + EncodingUtil.urlEncode(billingName, 'UTF-8');
            }
            if (String.isNotBlank(custEmail)) {
                body += '&billing_details[email]=' + EncodingUtil.urlEncode(custEmail, 'UTF-8');
            }
            if (String.isNotBlank(custPhone)) {
                body += '&billing_details[phone]=' + EncodingUtil.urlEncode(custPhone, 'UTF-8');
            }
            if (addressMap != null) {
                if (addressMap.get('line1') != null && String.isNotBlank(String.valueOf(addressMap.get('line1')))) {
                    body += '&billing_details[address][line1]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('line1')), 'UTF-8');
                }
                if (addressMap.get('line2') != null && String.isNotBlank(String.valueOf(addressMap.get('line2')))) {
                    body += '&billing_details[address][line2]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('line2')), 'UTF-8');
                }
                if (addressMap.get('city') != null && String.isNotBlank(String.valueOf(addressMap.get('city')))) {
                    body += '&billing_details[address][city]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('city')), 'UTF-8');
                }
                if (addressMap.get('state') != null && String.isNotBlank(String.valueOf(addressMap.get('state')))) {
                    body += '&billing_details[address][state]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('state')), 'UTF-8');
                }
                if (addressMap.get('postal_code') != null && String.isNotBlank(String.valueOf(addressMap.get('postal_code')))) {
                    body += '&billing_details[address][postal_code]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('postal_code')), 'UTF-8');
                }
                if (addressMap.get('country') != null && String.isNotBlank(String.valueOf(addressMap.get('country')))) {
                    body += '&billing_details[address][country]=' + EncodingUtil.urlEncode(String.valueOf(addressMap.get('country')), 'UTF-8');
                }
            }

            body += '&metadata[customer_id]=' + EncodingUtil.urlEncode(customerId, 'UTF-8');
            if (String.isNotBlank(custName)) {
                body += '&metadata[customer_name]=' + EncodingUtil.urlEncode(custName, 'UTF-8');
            }
            if (String.isNotBlank(custEmail)) {
                body += '&metadata[customer_email]=' + EncodingUtil.urlEncode(custEmail, 'UTF-8');
            }

            req.setBody(body);

            HttpResponse createRes = new Http().send(req);
            if (createRes.getStatusCode() < 200 || createRes.getStatusCode() >= 300) {
                throwStripeApiException(createRes, 'Create payment method');
            }

            Map<String, Object> methodData = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
            String paymentMethodId = (String) methodData.get('id');
            if (String.isBlank(paymentMethodId)) {
                throw new AuraHandledException('Stripe did not return a payment method ID.');
            }

            HttpRequest attachReq = new HttpRequest();
            attachReq.setEndpoint('https://api.stripe.com/v1/payment_methods/' + EncodingUtil.urlEncode(paymentMethodId, 'UTF-8') + '/attach');
            attachReq.setMethod('POST');
            attachReq.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            attachReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            attachReq.setTimeout(30000);
            attachReq.setBody('customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8'));

            HttpResponse attachRes = new Http().send(attachReq);
            if (attachRes.getStatusCode() >= 200 && attachRes.getStatusCode() < 300) {
                // If the customer has salesforce_account_id in metadata, sync this card to Salesforce
                if (metadataMap != null && metadataMap.containsKey('salesforce_account_id')) {
                    try {
                        Id sfAccId = Id.valueOf(String.valueOf(metadataMap.get('salesforce_account_id')));
                        syncPaymentCardsToSalesforce(sfAccId, customerId, new List<Object>{ methodData });
                    } catch (Exception ex) {
                        System.debug('Could not sync newly attached card to SF: ' + ex.getMessage());
                    }
                }
                return attachRes.getBody();
            }

            throwStripeApiException(attachRes, 'Attach payment method to customer');
            return null;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not attach payment method: ' + e.getMessage());
        }
    }

    /**
     * Helper to retrieve Stripe Customer details (name, email, phone, address).
     */
    private static Map<String, Object> retrieveStripeCustomer(String customerId) {
        if (String.isBlank(customerId)) return null;
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.stripe.com/v1/customers/' + EncodingUtil.urlEncode(customerId.trim(), 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            }
        } catch (Exception e) {
            System.debug('Error retrieving Stripe customer: ' + e.getMessage());
        }
        return null;
    }

    private static void throwStripeApiException(HttpResponse res, String actionName) {
        String message = actionName + ' failed';
        try {
            Map<String, Object> errResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> error = (Map<String, Object>) errResp.get('error');
            if (error != null && error.containsKey('message')) {
                message = (String) error.get('message');
            } else if (errResp.containsKey('message')) {
                message = (String) errResp.get('message');
            }
        } catch (Exception e) {
            message = actionName + ' failed with status: ' + res.getStatusCode();
        }

        throw new AuraHandledException(actionName + ': ' + message);
    }

    @AuraEnabled
    public static String listAllPaymentMethods(Integer limitUsed) {
        try {
            if (limitUsed == null) limitUsed = 100;
            if (limitUsed < 1) limitUsed = 1;
            if (limitUsed > 100) limitUsed = 100;

            List<Object> allCustomers = new List<Object>();
            String customerUrl = 'https://api.stripe.com/v1/customers?limit=' + limitUsed;

            while (String.isNotBlank(customerUrl)) {
                HttpRequest customerReq = new HttpRequest();
                customerReq.setEndpoint(customerUrl);
                customerReq.setMethod('GET');
                customerReq.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                customerReq.setTimeout(30000);
                HttpResponse customerRes = new Http().send(customerReq);

                if (customerRes.getStatusCode() < 200 || customerRes.getStatusCode() >= 300) {
                    throwStripeApiException(customerRes, 'List Stripe customers');
                    return null;
                }

                Map<String, Object> customerRoot = (Map<String, Object>) JSON.deserializeUntyped(customerRes.getBody());
                List<Object> customerData = (List<Object>) customerRoot.get('data');
                if (customerData != null) {
                    allCustomers.addAll(customerData);
                }
                Boolean hasMore = customerRoot.get('has_more') != null ? Boolean.valueOf(customerRoot.get('has_more')) : false;
                if (!hasMore || customerData == null || customerData.isEmpty()) {
                    break;
                }
                Map<String, Object> lastCustomer = (Map<String, Object>) customerData[customerData.size() - 1];
                String lastCustomerId = (String) lastCustomer.get('id');
                if (String.isBlank(lastCustomerId)) {
                    break;
                }

                customerUrl = 'https://api.stripe.com/v1/customers?limit=' + limitUsed + '&starting_after='
                    + EncodingUtil.urlEncode(lastCustomerId, 'UTF-8');
            }

            List<Object> allPaymentMethods = new List<Object>();

            for (Object customerObj : allCustomers) {
                Map<String, Object> customer = (Map<String, Object>) customerObj;
                String customerId = (String) customer.get('id');
                if (String.isBlank(customerId)) {
                    continue;
                }

                String paymentMethodUrl = 'https://api.stripe.com/v1/payment_methods?customer='
                    + EncodingUtil.urlEncode(customerId, 'UTF-8') + '&limit=' + limitUsed;

                while (String.isNotBlank(paymentMethodUrl)) {
                    HttpRequest pmReq = new HttpRequest();
                    pmReq.setEndpoint(paymentMethodUrl);
                    pmReq.setMethod('GET');
                    pmReq.setHeader('Authorization', 'Bearer ' + System.Label.Stripe_Access_token);
                    pmReq.setTimeout(30000);
                    HttpResponse pmRes = new Http().send(pmReq);

                    if (pmRes.getStatusCode() < 200 || pmRes.getStatusCode() >= 300) {
                        throwStripeApiException(pmRes, 'List payment methods for customer ' + customerId);
                        return null;
                    }
                    Map<String, Object> pmRoot = (Map<String, Object>) JSON.deserializeUntyped(pmRes.getBody());
                    List<Object> pmData = (List<Object>) pmRoot.get('data');
                    if (pmData != null) {
                        allPaymentMethods.addAll(pmData);
                    }
                    Boolean hasMore = pmRoot.get('has_more') != null
                        ? Boolean.valueOf(pmRoot.get('has_more'))
                        : false;
                    if (!hasMore || pmData == null || pmData.isEmpty()) {
                        break;
                    }
                    Map<String, Object> lastPaymentMethod = (Map<String, Object>) pmData[pmData.size() - 1];
                    String lastPaymentMethodId = (String) lastPaymentMethod.get('id');
                    if (String.isBlank(lastPaymentMethodId)) {
                        break;
                    }

                    paymentMethodUrl = 'https://api.stripe.com/v1/payment_methods?customer='
                        + EncodingUtil.urlEncode(customerId, 'UTF-8') + '&limit=' + limitUsed + '&starting_after='
                        + EncodingUtil.urlEncode(lastPaymentMethodId, 'UTF-8');
                }
            }

            Map<String, Object> response = new Map<String, Object>();
            response.put('data', allPaymentMethods);
            response.put('has_more', false);
            response.put('total_count', allPaymentMethods.size());
            return JSON.serialize(response);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not list all payment methods: ' + e.getMessage());
        }
    }
}