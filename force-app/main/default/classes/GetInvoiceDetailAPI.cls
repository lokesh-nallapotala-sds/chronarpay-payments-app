@RestResource(urlMapping='/getInvoicesDetailsAPI/')
global with sharing class GetInvoiceDetailAPI {

    @HttpGet
    global static void getInvoiceDetail() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        String billingDocNumber = req.params.get('billing_document_number');
        String docType = req.params.get('document_type');
        String customerNumber = req.params.get('customer_number');

        InvoiceResponse responseWrapper = new InvoiceResponse();

        try {
            if (String.isBlank(billingDocNumber)) {
                throw new CalloutException('billing_document_number parameter is required.');
            }

            // 1. Query the main Invoice record dynamically based on optional customer_number
            String query = 'SELECT Id, Name, Billing_Document_Number__c, Billing_Document_Type__c, ' +
                           'Payer_Account__r.AccountNumber, Payer_Account__r.company_code__c, ' +
                           'Sales_Organization__c, Distribution_Channel__c, Division__c, ' +
                           'Company_Code__c, Currency_Key__c, Document_Date__c, Due_Date__c, ' +
                           'Total_Amount__c, Open_Amount__c, Document_Status__c, Debit_Credit_Flag__c, ' +
                           'Document_Type__c ' +
                           'FROM Invoice__c ' +
                           'WHERE Billing_Document_Number__c = :billingDocNumber';
            
            if (String.isNotBlank(customerNumber)) {
                query += ' AND Payer_Account__r.AccountNumber = :customerNumber';
            }
            query += ' LIMIT 1';
            
            Invoice__c inv = Database.query(query);

            // 2. Query related Line Items
            List<Invoice_Line_Item__c> items = [
                SELECT Line_Number__c, Material_Number__c, Description__c,
                       Billed_Quantity__c, Sales_Unit__c, Base_Unit__c,
                       Pricing_Unit__c, Currency_Key__c, Total_Amount__c,
                       Open_Amount__c, Paid_Amount__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c = :inv.Id
            ];

            // 3. Query related Partners and their Account address info
            List<Invoice_Partner__c> partners = [
                SELECT Partner_Function__c, 
                       Account__r.AccountNumber,
                       Account__r.Name, 
                       Account__r.Name_2__c,
                       Account__r.BillingCity, 
                       Account__r.District__c,
                       Account__r.BillingStreet,
                       Account__r.BillingPostalCode, 
                       Account__r.BillingState, 
                       Account__r.BillingCountry
                FROM Invoice_Partner__c
                WHERE Invoice__c = :inv.Id
            ];

            // --- Construct Response Payload ---
            
            // Header Data
            HeaderData header = new HeaderData();
            header.billing_document_number = String.isNotBlank(inv.Billing_Document_Number__c) ? inv.Billing_Document_Number__c : inv.Name;
            header.billing_document_type = inv.Billing_Document_Type__c;
            header.soldto_number = (inv.Payer_Account__r != null && String.isNotBlank(inv.Payer_Account__r.AccountNumber)) ? inv.Payer_Account__r.AccountNumber : (inv.Payer_Account__r != null ? inv.Payer_Account__r.AccountNumber : null);
            header.sales_organization = inv.Sales_Organization__c;
            header.distribution_channel = inv.Distribution_Channel__c;
            header.division = inv.Division__c;
            header.company_code = inv.Payer_Account__r.company_code__c;
            header.currency_key = inv.Currency_Key__c;
            
            // Format dates as MM-dd-yyyy if not null
            if (inv.Document_Date__c != null) {
                header.document_date = Datetime.newInstance(inv.Document_Date__c.year(), inv.Document_Date__c.month(), inv.Document_Date__c.day()).format('MM-dd-yyyy');
            }
            if (inv.Due_Date__c != null) {
                header.due_date = Datetime.newInstance(inv.Due_Date__c.year(), inv.Due_Date__c.month(), inv.Due_Date__c.day()).format('MM-dd-yyyy');
            }
            
            header.total_amount = inv.Total_Amount__c;
            header.open_amount = inv.Open_Amount__c;
            header.document_status = inv.Document_Status__c;
            header.debit_credit_flag = inv.Debit_Credit_Flag__c;

            // Item Data
            List<ItemData> itemDataList = new List<ItemData>();
            for (Invoice_Line_Item__c item : items) {
                ItemData iData = new ItemData();
                iData.item_number = item.Line_Number__c != null ? Integer.valueOf(item.Line_Number__c) : null;
                iData.material_number = item.Material_Number__c;
                iData.description = item.Description__c;
                iData.billed_quantity = item.Billed_Quantity__c;
                iData.sales_unit = item.Sales_Unit__c;
                iData.base_unit = item.Base_Unit__c;
                iData.pricing_unit = item.Pricing_Unit__c;
                iData.currency_key = item.Currency_Key__c;
                iData.total_amount = item.Total_Amount__c;
                iData.open_amount = item.Open_Amount__c;
                iData.paid_amount = item.Paid_Amount__c;
                itemDataList.add(iData);
            }

            // Partner Data
            List<PartnerData> partnerDataList = new List<PartnerData>();
            for (Invoice_Partner__c partner : partners) {
                PartnerData pData = new PartnerData();
                pData.partner_function = partner.Partner_Function__c;
                pData.partner_number = (partner.Account__r != null && String.isNotBlank(partner.Account__r.AccountNumber)) ? partner.Account__r.AccountNumber : (partner.Account__r != null ? partner.Account__r.AccountNumber : null);

                if (partner.Account__r != null) {
                    AddressData addr = new AddressData();
                    addr.name = partner.Account__r.Name;
                    addr.name_2 = partner.Account__r.Name_2__c;
                    addr.city = partner.Account__r.BillingCity;
                    addr.district = partner.Account__r.District__c;
                    addr.street = partner.Account__r.BillingStreet;
                    addr.postal_code_city = partner.Account__r.BillingPostalCode;
                    addr.region = partner.Account__r.BillingState;
                    addr.country = partner.Account__r.BillingCountry;
                    pData.address_data = addr;
                }
                partnerDataList.add(pData);
            }

            Detail detail = new Detail();
            detail.header_data = header;
            detail.item_data = itemDataList;
            detail.partner_data = partnerDataList;

            Status status = new Status();
            status.message_type = 'S';
            status.message_identification = '/CNBS/X_API';
            status.message_number = 10;
            status.message_line_string = 'Request successfully processed';

            responseWrapper.detail = detail;
            responseWrapper.status = status;

            res.statusCode = 200;

        } catch (Exception e) {
            Status status = new Status();
            status.message_type = 'E';
            status.message_identification = '/CNBS/X_API';
            status.message_number = 500;
            status.message_line_string = e.getMessage();
            responseWrapper.status = status;
            
            // Set correct HTTP Status Code
            if (e.getMessage().contains('required')) {
                res.statusCode = 400;
            } else if (e.getTypeName() == 'System.QueryException') {
                res.statusCode = 404;
                status.message_line_string = 'Invoice not found.';
            } else {
                res.statusCode = 500;
            }
        }

        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(responseWrapper));
    }

    // --- Inner Classes ---
    global class InvoiceResponse {
        public Detail detail { get; set; }
        public Status status { get; set; }
    }

    global class Detail {
        public HeaderData header_data { get; set; }
        public List<ItemData> item_data { get; set; }
        public List<PartnerData> partner_data { get; set; }
    }

    global class HeaderData {
        public String billing_document_number { get; set; }
        public String billing_document_type { get; set; }
        public String soldto_number { get; set; }
        public String sales_organization { get; set; }
        public String distribution_channel { get; set; }
        public String division { get; set; }
        public String company_code { get; set; }
        public String currency_key { get; set; }
        public String document_date { get; set; }
        public String due_date { get; set; }
        public Decimal total_amount { get; set; }
        public Decimal open_amount { get; set; }
        public String document_status { get; set; }
        public String debit_credit_flag { get; set; }
    }

    global class ItemData {
        public Integer item_number { get; set; }
        public String material_number { get; set; }
        public String description { get; set; }
        public Decimal billed_quantity { get; set; }
        public String sales_unit { get; set; }
        public String base_unit { get; set; }
        public String pricing_unit { get; set; }
        public String currency_key { get; set; }
        public Decimal total_amount { get; set; }
        public Decimal open_amount { get; set; }
        public Decimal paid_amount { get; set; }
    }

    global class PartnerData {
        public String partner_function { get; set; }
        public String partner_number { get; set; }
        public AddressData address_data { get; set; }
    }

    global class AddressData {
        public String name { get; set; }
        public String name_2 { get; set; }
        public String city { get; set; }
        public String district { get; set; }
        public String street { get; set; }
        public String postal_code_city { get; set; }
        public String region { get; set; }
        public String country { get; set; }
    }

    global class Status {
        public String message_type { get; set; }
        public String message_identification { get; set; }
        public Integer message_number { get; set; }
        public String message_line_string { get; set; }
    }
}