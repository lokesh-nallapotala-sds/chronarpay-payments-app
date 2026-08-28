@RestResource(urlMapping='/getInvoiceList/*')
global with sharing class GetInvoiceListAPI {

    @HttpGet
    global static void getInvoiceDocumentList() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        ResponseWrapper responseObj = new ResponseWrapper();

        try {
            String payerNumber = requestParam(req, 'payer_number', new List<String>{'payer_data', 'customer_number'});
            String companyCode = requestParam(req, 'company_code', new List<String>{'payer_data', 'company_code'});
            String documentType = requestParam(req, 'document_type', new List<String>{'search_parameters', 'document_type'});
            String documentSearchStatus = requestParam(req, 'document_search_status', new List<String>{'search_parameters', 'status'});
            String soldToNumber = requestParam(req, 'soldto_number', new List<String>{'soldto_data', 'customer_number'});
            String salesOrganization = requestParam(req, 'sales_organization', new List<String>{'soldto_data', 'sales_area_data', 'sales_organization'});
            String distributionChannel = requestParam(req, 'distribution_channel', new List<String>{'soldto_data', 'sales_area_data', 'distribution_channel'});
            String division = requestParam(req, 'division', new List<String>{'soldto_data', 'sales_area_data', 'division'});
            String dateFrom = requestParam(req, 'date_from', new List<String>{'search_parameters', 'date_from'});
            String dateTo = requestParam(req, 'date_to', new List<String>{'search_parameters', 'date_to'});
            String dueDateFrom = requestParam(req, 'due_date_from', new List<String>{'search_parameters', 'due_date_from'});
            String dueDateTo = requestParam(req, 'due_date_to', new List<String>{'search_parameters', 'due_date_to'});
            String currencyKey = requestParam(req, 'currency_key', new List<String>{'search_parameters', 'currency_key'});

            if (String.isBlank(payerNumber) || String.isBlank(companyCode) || String.isBlank(documentType) || String.isBlank(documentSearchStatus)) {
                throw new CalloutException('payer_number, company_code, document_type and document_search_status are required.');
            }

            String invoiceSoql = 'SELECT Id, Billing_Document_Number__c, Billing_Document_Type__c, Finance_Document_Number__c, ' +
                'Document_Item_Number__c, Finance_Document_Type__c, Reference_Document_Number__c, Document_Fiscal_Year__c, ' +
                'Currency_Key__c, Posting_Date__c, Document_Date__c, Due_Date__c, Total_Amount__c, ' +
                'Open_Amount__c, Payer_Account__r.company_code__c, Paid_Amount__c ' +
                //, Paid_Amount__c, Discount_Amount__c, PDF_Document_Available__c 
                'FROM Invoice__c ' +
                'WHERE Payer_Account__r.company_code__c = :companyCode AND Billing_Document_Type__c = :documentType';

            if (documentSearchStatus == '02' || documentSearchStatus == '03') {
                Date fromDate = parseDate(dateFrom);
                Date toDate = parseDate(dateTo);
                if (fromDate != null) {
                    invoiceSoql += ' AND Posting_Date__c >= :fromDate';
                }
                if (toDate != null) {
                    invoiceSoql += ' AND Posting_Date__c <= :toDate';
                }
            }
            if (!String.isBlank(dueDateFrom)) {
                Date fromDueDate = parseDate(dueDateFrom);
                if (fromDueDate != null) {
                    invoiceSoql += ' AND Due_Date__c >= :fromDueDate';
                }
            }
            if (!String.isBlank(dueDateTo)) {
                Date toDueDate = parseDate(dueDateTo);
                if (toDueDate != null) {
                    invoiceSoql += ' AND Due_Date__c <= :toDueDate';
                }
            }
            if (!String.isBlank(currencyKey)) {
                invoiceSoql += ' AND Currency_Key__c = :currencyKey';
            }

            List<Invoice__c> invoices = Database.query(invoiceSoql);
            Set<Id> invoiceIds = new Set<Id>();
            for (Invoice__c invoiceRecord : invoices) {
                invoiceIds.add(invoiceRecord.Id);
            }

            //Map<Id, Invoice_Partner__c> invoiceToPartner = new Map<Id, Invoice_Partner__c>();
            Map<Id, List<Invoice_Partner__c>> invoiceToPartner = new Map<Id, List<Invoice_Partner__c>>();
            Map<Id, List<Invoice_Line_Item__c>> invoiceToLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
            if (!invoiceIds.isEmpty()) {
                String partnerSoql = 'SELECT Invoice__c, Account__r.AccountNumber, Account__r.Sales_Organization__c, ' +
                    'Account__r.Distribution_Channel__c, Account__r.Division__c, Partner_Function__c FROM Invoice_Partner__c WHERE Invoice__c IN :invoiceIds AND Account__r.Type IN (\'Payer\', \'Sold-To\')';
                //String soldToPartnerSoql = 'SELECT Invoice__c, Account__r.AccountNumber, Account__r.Sales_Organization__c, ' +
                  //  'Account__r.Distribution_Channel__c, Account__r.Division__c, Partner_Function__c FROM Invoice_Partner__c WHERE Invoice__c IN :invoiceIds AND Account__r.Type = \'Sold-To\'';

                if (!String.isBlank(payerNumber)) {
                    partnerSoql += ' AND Account__r.AccountNumber = :payerNumber';
                }
                if (!String.isBlank(soldToNumber)) {
                    partnerSoql += ' AND Account__r.AccountNumber = :soldToNumber';
                }
                if (!String.isBlank(salesOrganization)) {
                    partnerSoql += ' AND Account__r.Sales_Organization__c = :salesOrganization';
                    //soldToPartnerSoql += ' AND Account__r.Sales_Organization__c = :salesOrganization';
                }
                if (!String.isBlank(distributionChannel)) {
                    partnerSoql += ' AND Account__r.Distribution_Channel__c = :distributionChannel';
                    //soldToPartnerSoql += ' AND Account__r.Distribution_Channel__c = :distributionChannel';
                }
                if (!String.isBlank(division)) {
                    partnerSoql += ' AND Account__r.Division__c = :division';
                    //soldToPartnerSoql += ' AND Account__r.Division__c = :division';
                }

                List<Invoice_Partner__c> partners = Database.query(partnerSoql);
                //List<Invoice_Partner__c> soldToPartners = Database.query(soldToPartnerSoql);
                for (Invoice_Partner__c partnerRecord : partners) {system.debug('partnerRecord ==> '+partnerRecord);
                    if (!invoiceToPartner.containsKey(partnerRecord.Invoice__c)) {
                        invoiceToPartner.put(partnerRecord.Invoice__c, new List<Invoice_Partner__c>());
                    }
                    invoiceToPartner.get(partnerRecord.Invoice__c).add(partnerRecord);
                }

                /*for (Invoice_Line_Item__c lineItemRecord : [
                    SELECT Invoice__c, Line_Number__c, Currency_Key__c, Total_Amount__c, Open_Amount__c, Paid_Amount__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c IN :invoiceIds
                ]) {
                    if (!invoiceToLineItems.containsKey(lineItemRecord.Invoice__c)) {
                        invoiceToLineItems.put(lineItemRecord.Invoice__c, new List<Invoice_Line_Item__c>());
                    }
                    invoiceToLineItems.get(lineItemRecord.Invoice__c).add(lineItemRecord);
                }*/
            }

            List<DocumentWrapper> documentList = new List<DocumentWrapper>();
            for (Invoice__c invoiceRecord : invoices) {system.debug('invoiceRecord ==> '+invoiceRecord);
                //Invoice_Partner__c matchingPartner = invoiceToPartner.get(invoiceRecord.Id);
                List<Invoice_Partner__c> matchingPartners = invoiceToPartner.get(invoiceRecord.Id);
                if (matchingPartners == null) {
                    continue;
                }
                String salesOrg = null;
                String distChannel = null;
                String div = null;
                String payerNo = null;
                String soldToNo = null;
                if (matchingPartners != null) {
                    for (Invoice_Partner__c matchingPartner : matchingPartners) {system.debug('matchingPartner ==> '+matchingPartner);
                        if(matchingPartner.Partner_Function__c == 'RG') {
                            salesOrg = matchingPartner.Account__r.Sales_Organization__c;
                            distChannel = matchingPartner.Account__r.Distribution_Channel__c;
                            div = matchingPartner.Account__r.Division__c;
                            payerNo = matchingPartner.Account__r.AccountNumber;
                        }
                        if(matchingPartner.Partner_Function__c == 'AG') {
                            soldToNo = matchingPartner.Account__r.AccountNumber;
                        }
                        //documentList.add(buildDocument(invoiceRecord, matchingPartner, null));
                    }
                }
                //List<Invoice_Line_Item__c> lineItems = invoiceToLineItems.get(invoiceRecord.Id);
                //if (lineItems == null || lineItems.isEmpty()) {
                    documentList.add(buildDocument(invoiceRecord, salesOrg, distChannel, div, payerNo, soldToNo, null));
                    //continue;
                //}

                /*for (Invoice_Line_Item__c lineItemRecord : lineItems) {
                    documentList.add(buildDocument(invoiceRecord, matchingPartner, lineItemRecord));
                }*/
            }

            responseObj.document_list = documentList;
            responseObj.status = buildStatus('S', 'Request successfully processed ,document selected ' + documentList.size());
            res.statusCode = 200;
        } catch (QueryException qe) {
            responseObj.document_list = new List<DocumentWrapper>();
            responseObj.status = buildStatus('S', 'Request successfully processed ,document selected 0');
            res.statusCode = 200;
        } catch (Exception e) {
            responseObj.status = buildStatus('E', e.getMessage() + ' | Line: ' + e.getLineNumber());
            res.statusCode = 500;
        }

        if (res != null) {
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(responseObj));
        }
    }

    private static DocumentWrapper buildDocument(Invoice__c invoiceRecord, String salesOrg, String distChannel, String div, String payerNo, String soldToNo, Invoice_Line_Item__c lineItemRecord) {
        DocumentWrapper document = new DocumentWrapper();
        document.billing_document_number = invoiceRecord.Billing_Document_Number__c;
        document.billing_document_type = invoiceRecord.Billing_Document_Type__c;
        document.document_number_finance = invoiceRecord.Finance_Document_Number__c;
        document.finance_document_type = invoiceRecord.Finance_Document_Type__c;
        document.reference_number = invoiceRecord.Reference_Document_Number__c;
        document.fiscal_year_of_the_relevant_invoice = invoiceRecord.Document_Fiscal_Year__c != null ? Integer.valueOf(invoiceRecord.Document_Fiscal_Year__c) : null;
        document.posting_date = formatDate(invoiceRecord.Posting_Date__c);
        document.document_date = formatDate(invoiceRecord.Document_Date__c);
        document.due_date = formatDate(invoiceRecord.Due_Date__c);
        document.days_in_arrears = null;
        document.currency_key = invoiceRecord.Currency_Key__c;
        document.total_amount = invoiceRecord.Total_Amount__c;
        document.open_amount = invoiceRecord.Open_Amount__c;
        document.paid_amount = invoiceRecord.Paid_Amount__c;
        document.line_item_in_the_relevant_invoice = 1;

        /*if (lineItemRecord != null) {
            document.line_item_in_the_relevant_invoice = lineItemRecord.Line_Number__c != null ? Integer.valueOf(lineItemRecord.Line_Number__c) : null;
            document.currency_key = lineItemRecord.Currency_Key__c;
            document.total_amount = lineItemRecord.Total_Amount__c;
            document.open_amount = lineItemRecord.Open_Amount__c;
            document.paid_amount = lineItemRecord.Paid_Amount__c;
        } else {
            document.line_item_in_the_relevant_invoice = invoiceRecord.Document_Item_Number__c != null ? Integer.valueOf(invoiceRecord.Document_Item_Number__c) : null;
        }*/

        /*if (partnerRecord != null && partnerRecord.Account__r != null) {
            document.sales_organization = partnerRecord.Account__r.Sales_Organization__c;
            document.distribution_channel = partnerRecord.Account__r.Distribution_Channel__c;
            document.division = partnerRecord.Account__r.Division__c;
            document.soldto_number = partnerRecord.Account__r.AccountNumber;
            document.payer_number = partnerRecord.Account__r.AccountNumber;
        }*/
        if (!String.isBlank(salesOrg)) {
            document.sales_organization = salesOrg;
        }
        if (!String.isBlank(distChannel)) {
            document.distribution_channel = distChannel;
        }
        if (!String.isBlank(div)) {
            document.division = div;
        }
        if (!String.isBlank(payerNo)) {
            document.payer_number = payerNo;
        }
        if (!String.isBlank(soldToNo)) {
            document.soldto_number = soldToNo;
        }

        return document;
    }

    private static String requestParam(RestRequest req, String paramName, List<String> bodyPath) {
        String value = req != null ? req.params.get(paramName) : null;
        if (!String.isBlank(value)) {
            return value;
        }

        if (req != null && req.requestBody != null && req.requestBody.size() > 0) {
            try {
                Object bodyObject = JSON.deserializeUntyped(req.requestBody.toString());
                if (bodyObject instanceof Map<String, Object>) {
                    Map<String, Object> bodyMap = (Map<String, Object>) bodyObject;
                    Object currentValue = bodyMap;
                    for (String pathKey : bodyPath) {
                        if (!(currentValue instanceof Map<String, Object>)) {
                            return null;
                        }
                        currentValue = ((Map<String, Object>) currentValue).get(pathKey);
                        if (currentValue == null) {
                            return null;
                        }
                    }
                    return currentValue == null ? null : String.valueOf(currentValue);
                }
            } catch (Exception e) {
                return null;
            }
        }

        return null;
    }

    private static Date parseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            List<String> parts = value.split('-');
            if (parts.size() != 3) {
                return null;
            }
            Integer month = Integer.valueOf(parts[0]);
            Integer day = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);
            return Date.newInstance(year, month, day);
        } catch (Exception e) {
            return null;
        }
    }

    private static String formatDate(Date value) {
        return value == null ? null : DateTime.newInstance(value.year(), value.month(), value.day()).format('MM-dd-yyyy');
    }

    private static StatusWrapper buildStatus(String messageType, String messageLineString) {
        StatusWrapper status = new StatusWrapper();
        status.message_type = messageType;
        status.message_identification = '/CNBS/X_API';
        status.message_number = messageType == 'S' ? 10 : 500;
        status.message_line_string = messageLineString;
        return status;
    }

    global class ResponseWrapper {
        public List<DocumentWrapper> document_list;
        public StatusWrapper status;
    }

    global class StatusWrapper {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;
    }

    global class DocumentWrapper {
        public String billing_document_number;
        public String billing_document_type;
        public String sales_organization;
        public String distribution_channel;
        public String division;
        public String document_number_finance;
        public Integer line_item_in_the_relevant_invoice;
        public String finance_document_type;
        public String reference_number;
        public Integer fiscal_year_of_the_relevant_invoice;
        public String soldto_number;
        public String payer_number;
        public String posting_date;
        public String document_date;
        public String due_date;
        public String days_in_arrears;
        public String currency_key;
        public Decimal total_amount;
        public Decimal open_amount;
        public Decimal paid_amount;
        public Decimal discount_amount;
        public String pdf_document_available;
    }
}