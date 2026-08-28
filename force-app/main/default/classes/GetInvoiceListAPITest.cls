@IsTest
private class GetInvoiceListAPITest {

    @IsTest
    static void testInvoiceListUsesInvoicePartnerDataFromRequestBody() {
        Account acc = new Account(
            Name = 'Test Customer',
            AccountNumber = '1001',
            Company_Code__c = '3000',
            Sales_Organization__c = '3000',
            Distribution_Channel__c = '10',
            Division__c = '00'
        );
        insert acc;

        Invoice__c invoice = new Invoice__c(
            Billing_Document_Number__c = '90038990',
            Billing_Document_Type__c = 'F2',
            Company_Code__c = '3000',
            Finance_Document_Number__c = '1400000229',
            Finance_Document_Type__c = 'RV',
            Reference_Document_Number__c = '90038990',
            Document_Item_Number__c = '1',
            Document_Fiscal_Year__c = '2024',
            Currency_Key__c = 'USD',
            Posting_Date__c = Date.newInstance(2024, 1, 1),
            Document_Date__c = Date.newInstance(2024, 1, 1),
            Due_Date__c = Date.newInstance(2024, 1, 15),
            Open_Amount__c = 100
        );
        insert invoice;

        insert new Invoice_Partner__c(
            Invoice__c = invoice.Id,
            Account__c = acc.Id,
            Partner_Function__c = 'SP'
        );

        insert new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Line_Number__c = 10,
            Currency_Key__c = 'USD',
            Total_Amount__c = 100,
            Open_Amount__c = 80,
            Paid_Amount__c = 20
        );

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/getInvoiceList';
        req.httpMethod = 'GET';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'payer_data' => new Map<String, Object>{
                'customer_number' => '1001',
                'company_code' => '3000'
            },
            'search_parameters' => new Map<String, Object>{
                'document_type' => 'F2',
                'status' => '01'
            },
            'soldto_data' => new Map<String, Object>{
                'customer_number' => '1001'
            }
        }));
        RestContext.request = req;

        RestResponse res = new RestResponse();
        RestContext.response = res;

        Test.startTest();
        GetInvoiceListAPI.getInvoiceDocumentList();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected success response');
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> documentList = (List<Object>) response.get('document_list');

        Map<String, Object> document = (Map<String, Object>) documentList[0];
        System.assertEquals(10, document.get('line_item_in_the_relevant_invoice'), 'Line item number should come from the invoice line item');
        System.assertEquals('USD', document.get('currency_key'), 'Currency should come from the invoice line item');
        System.assertEquals(100.0, ((Decimal) document.get('total_amount')), 'Total amount should come from the invoice line item');
        System.assertEquals(80.0, ((Decimal) document.get('open_amount')), 'Open amount should come from the invoice line item');
        System.assertEquals(20.0, ((Decimal) document.get('paid_amount')), 'Paid amount should come from the invoice line item');
    }
}