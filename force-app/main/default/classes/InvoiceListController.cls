public without sharing class InvoiceListController {

    @AuraEnabled(cacheable=true)
    public static List<PayerAccountWrapper> getPayerAccounts() {
        Set<Id> accountIdsWithInvoices = new Set<Id>();
        List<Invoice__c> invoices = [
            SELECT Id, Payer_Account__c
            FROM Invoice__c
            WHERE Payer_Account__c != NULL
        ];
        for (Invoice__c inv : invoices) {
            accountIdsWithInvoices.add(inv.Payer_Account__c);
        }

        // First check if current user owns any payer accounts (for internal users)
        List<Account> accounts = [
            SELECT Id, Name, AccountNumber, sales_organization__c
            FROM Account
            WHERE Type = 'Payer' AND OwnerId = :UserInfo.getUserId() AND Id IN :accountIdsWithInvoices
            ORDER BY Name
        ];

        // If empty (e.g. Community / Portal / Guest user), query all payer accounts with invoices
        if (accounts.isEmpty()) {
            accounts = [
                SELECT Id, Name, AccountNumber, sales_organization__c
                FROM Account
                WHERE Type = 'Payer' AND Id IN :accountIdsWithInvoices
                ORDER BY Name
            ];
        }

        // If still empty, query all Payer accounts
        if (accounts.isEmpty()) {
            accounts = [
                SELECT Id, Name, AccountNumber, sales_organization__c
                FROM Account
                WHERE Type = 'Payer'
                ORDER BY Name
            ];
        }

        List<PayerAccountWrapper> wrappers = new List<PayerAccountWrapper>();
        for (Account accountRecord : accounts) {
            wrappers.add(new PayerAccountWrapper(
                accountRecord.Id,
                accountRecord.Name,
                accountRecord.AccountNumber,
                accountRecord.sales_organization__c
            ));
        }
        return wrappers;
    }

    @AuraEnabled
    public static List<InvoiceWrapper> getInvoicesByPayerAccountId(Id payerAccountId) {
        if (payerAccountId == null) {
            return new List<InvoiceWrapper>();
        }

        List<Invoice__c> invoices = [
            SELECT Id,
                   Billing_Document_Number__c,
                   Reference_Document_Number__c,
                   Document_Date__c,
                   Due_Date__c,
                   Total_Amount__c,
                   Open_Amount__c,
                   Paid_Amount__c,
                   Currency_Key__c,
                   Payer_Account__c,
                   Payer_Account__r.AccountNumber,
                   Sold_To_Account__c,
                   Sold_To_Account__r.AccountNumber,
                   Sold_To_Account__r.Name
            FROM Invoice__c
            WHERE Payer_Account__c = :payerAccountId
            ORDER BY Document_Date__c DESC NULLS LAST, Billing_Document_Number__c
        ];

        List<InvoiceWrapper> wrappers = new List<InvoiceWrapper>();
        for (Invoice__c invoiceRecord : invoices) {
            wrappers.add(new InvoiceWrapper(
                invoiceRecord.Id,
                invoiceRecord.Billing_Document_Number__c,
                invoiceRecord.Reference_Document_Number__c,
                invoiceRecord.Document_Date__c,
                invoiceRecord.Due_Date__c,
                invoiceRecord.Total_Amount__c,
                invoiceRecord.Open_Amount__c,
                invoiceRecord.Paid_Amount__c,
                invoiceRecord.Currency_Key__c,
                invoiceRecord.Payer_Account__c,
                invoiceRecord.Payer_Account__r != null ? invoiceRecord.Payer_Account__r.AccountNumber : null,
                invoiceRecord.Sold_To_Account__c,
                invoiceRecord.Sold_To_Account__r != null ? invoiceRecord.Sold_To_Account__r.AccountNumber : null,
                invoiceRecord.Sold_To_Account__r != null ? invoiceRecord.Sold_To_Account__r.Name : null
            ));
        }
        return wrappers;
    }

    @AuraEnabled
    public static List<SoldToAccountWrapper> getSoldToAccountsByPayerAccountId(Id payerAccountId) {
        if (payerAccountId == null) {
            return new List<SoldToAccountWrapper>();
        }

        Map<Id, SoldToAccountWrapper> soldToMap = new Map<Id, SoldToAccountWrapper>();

        // 1. Query from Account_Relationship__c (SoldTo accounts linked to this Payer)
        List<Account_Relationship__c> relationships = [
            SELECT Id, SoldTo_Account__c, SoldTo_Account__r.Name,
                   SoldTo_Account__r.AccountNumber, SoldTo_Account__r.sales_organization__c
            FROM Account_Relationship__c
            WHERE Payer_Account__c = :payerAccountId AND SoldTo_Account__c != NULL
            ORDER BY SoldTo_Account__r.Name ASC
        ];
        for (Account_Relationship__c rel : relationships) {
            if (rel.SoldTo_Account__c != null && !soldToMap.containsKey(rel.SoldTo_Account__c)) {
                soldToMap.put(rel.SoldTo_Account__c, new SoldToAccountWrapper(
                    rel.SoldTo_Account__c,
                    rel.SoldTo_Account__r.Name,
                    rel.SoldTo_Account__r.AccountNumber,
                    rel.SoldTo_Account__r.sales_organization__c
                ));
            }
        }

        // 2. Also include any Sold_To_Account__c from Invoices for this Payer
        List<Invoice__c> invoices = [
            SELECT Sold_To_Account__c, Sold_To_Account__r.Name,
                   Sold_To_Account__r.AccountNumber, Sold_To_Account__r.sales_organization__c
            FROM Invoice__c
            WHERE Payer_Account__c = :payerAccountId AND Sold_To_Account__c != NULL
            ORDER BY Sold_To_Account__r.Name ASC
        ];
        for (Invoice__c inv : invoices) {
            if (inv.Sold_To_Account__c != null && !soldToMap.containsKey(inv.Sold_To_Account__c)) {
                soldToMap.put(inv.Sold_To_Account__c, new SoldToAccountWrapper(
                    inv.Sold_To_Account__c,
                    inv.Sold_To_Account__r.Name,
                    inv.Sold_To_Account__r.AccountNumber,
                    inv.Sold_To_Account__r.sales_organization__c
                ));
            }
        }

        return soldToMap.values();
    }

    private static Integer processInvoicePayments(List<InvoicePaymentUpdate> invoicePayments) {
        if (invoicePayments == null || invoicePayments.isEmpty()) {
            return 0;
        }

        Map<Id, Decimal> paymentAmounts = new Map<Id, Decimal>();
        for (InvoicePaymentUpdate updateInv : invoicePayments) {
            if (updateInv == null || updateInv.invoiceId == null || updateInv.paymentAmount == null) {
                continue;
            }
            if (updateInv.paymentAmount <= 0) {
                continue;
            }
            paymentAmounts.put(updateInv.invoiceId, updateInv.paymentAmount);
        }

        if (paymentAmounts.isEmpty()) {
            return 0;
        }

        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, Open_Amount__c, Paid_Amount__c
            FROM Invoice__c
            WHERE Id IN :paymentAmounts.keySet()
            FOR UPDATE
        ];

        List<Invoice__c> updates = new List<Invoice__c>();
        for (Invoice__c invoiceRecord : invoicesToUpdate) {
            Decimal payAmount = paymentAmounts.get(invoiceRecord.Id);
            Decimal existingOpen = invoiceRecord.Open_Amount__c != null ? invoiceRecord.Open_Amount__c : 0;
            Decimal existingPaid = invoiceRecord.Paid_Amount__c != null ? invoiceRecord.Paid_Amount__c : 0;
            Decimal nextOpen = existingOpen - payAmount;

            if (existingOpen > 0 && nextOpen < 0) {
                nextOpen = 0;
            } else if (existingOpen < 0 && nextOpen > 0) {
                nextOpen = 0;
            }

            invoiceRecord.Open_Amount__c = nextOpen;
            invoiceRecord.Paid_Amount__c = existingPaid + payAmount;
            updates.add(invoiceRecord);
        }

        if (!updates.isEmpty()) {
            update updates;
        }
        return updates.size();
    }

    @AuraEnabled
    public static Integer applyInvoicePaymentsJson(String invoicePaymentsJson) {
        if (String.isBlank(invoicePaymentsJson)) {
            return 0;
        }

        List<InvoicePaymentUpdate> invoicePayments;
        try {
            invoicePayments = (List<InvoicePaymentUpdate>) JSON.deserialize(invoicePaymentsJson, List<InvoicePaymentUpdate>.class);
        } catch (Exception ex) {
            return 0;
        }

        if (invoicePayments == null || invoicePayments.isEmpty()) {
            return 0;
        }

        return processInvoicePayments(invoicePayments);
    }

    public class PayerAccountWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String salesOrganization;

        public PayerAccountWrapper(Id accountId, String accountName, String accountNumber, String salesOrganization) {
            this.accountId = accountId;
            this.accountName = accountName;
            this.accountNumber = accountNumber;
            this.salesOrganization = salesOrganization;
        }
    }

    public class SoldToAccountWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String salesOrganization;

        public SoldToAccountWrapper(Id accountId, String accountName, String accountNumber, String salesOrganization) {
            this.accountId = accountId;
            this.accountName = accountName;
            this.accountNumber = accountNumber;
            this.salesOrganization = salesOrganization;
        }
    }

    public class InvoiceWrapper {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String billingDocumentNumber;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public String documentDate;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal openAmount;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public String currencyKey;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String soldToAccountId;
        @AuraEnabled public String soldToAccountNumber;
        @AuraEnabled public String soldToAccountName;
        @AuraEnabled public String status;

        public InvoiceWrapper(
            Id invoiceId,
            String billingDocumentNumber,
            String referenceNumber,
            Date documentDate,
            Date dueDate,
            Decimal totalAmount,
            Decimal openAmount,
            Decimal paidAmount,
            String currencyKey,
            String accountId,
            String accountNumber
        ) {
            this(invoiceId, billingDocumentNumber, referenceNumber, documentDate, dueDate, totalAmount, openAmount, paidAmount, currencyKey, accountId, accountNumber, null, null, null);
        }

        public InvoiceWrapper(
            Id invoiceId,
            String billingDocumentNumber,
            String referenceNumber,
            Date documentDate,
            Date dueDate,
            Decimal totalAmount,
            Decimal openAmount,
            Decimal paidAmount,
            String currencyKey,
            String accountId,
            String accountNumber,
            String soldToAccountId,
            String soldToAccountNumber,
            String soldToAccountName
        ) {
            this.invoiceId = invoiceId;
            this.billingDocumentNumber = billingDocumentNumber;
            this.referenceNumber = referenceNumber;
            this.documentDate = documentDate != null ? documentDate.format() : null;
            this.dueDate = dueDate != null ? dueDate.format() : null;
            this.totalAmount = totalAmount != null ? totalAmount : 0;
            this.openAmount = openAmount != null ? openAmount : 0;
            this.paidAmount = paidAmount != null ? paidAmount : 0;
            this.currencyKey = String.isNotBlank(currencyKey) ? currencyKey : 'USD';
            this.accountId = accountId;
            this.accountNumber = accountNumber;
            this.soldToAccountId = soldToAccountId;
            this.soldToAccountNumber = soldToAccountNumber;
            this.soldToAccountName = soldToAccountName;
            this.status = this.openAmount == 0 ? 'Paid' : 'Open';
        }
    }

    public class InvoicePaymentUpdate {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public Decimal paymentAmount;
    }
}