@RestResource(urlMapping='/CNBS/Accounts/*')
global with sharing class CNBSAccountAPI {

    @HttpGet
    global static void getAccountDetails() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String accountId = req.requestURI.substring(req.requestURI.lastIndexOf('/')+1);
        
        Map<String, Object> response = new Map<String, Object>();
        
        try {
            // Query Payer Account
            Account payer = [
                SELECT Id, account_id__c, AccountNumber, sales_organization__c, distribution_channel__c, 
                       division__c, company_code__c, Name, BillingCity, BillingStreet, BillingPostalCode, 
                       BillingState, BillingCountry, Phone 
                FROM Account 
                WHERE Id = :accountId 
                LIMIT 1
            ];
            
            // Query Sold-To Accounts
            List<Account> soldTos = [
                SELECT Id, AccountNumber, sales_organization__c, distribution_channel__c, 
                       division__c, Name, BillingCity, BillingStreet, BillingPostalCode, BillingState, BillingCountry 
                FROM Account 
                WHERE ParentId = :accountId
            ];
            
            // Query Payment Cards
            List<Payment_Method__c> cards = [
                SELECT Id, Card_Type__c, Card_Token__c, Cardholder_Name__c, Valid_From__c, Valid_To__c, Is_Default__c, Last_Four__c 
                FROM Payment_Method__c 
                WHERE Account__c = :accountId
            ];
            
            // Query Auto Pay Enrollments
            List<Auto_Pay_Enrollment__c> autoPays = [
                SELECT Id, Company_Code__c, Payment_Type__c, Is_Enrolled__c, Payment_Method__r.Card_Token__c 
                FROM Auto_Pay_Enrollment__c 
                WHERE Account__c = :accountId
            ];
            
            // Build Payer Det -> Address Data
            Map<String, Object> addressData = new Map<String, Object>{
                'name' => payer.Name,
                'city' => payer.BillingCity,
                'street' => payer.BillingStreet,
                'postal_code_city' => payer.BillingPostalCode,
                'region' => payer.BillingState,
                'country' => payer.BillingCountry
            };

            // Build Payer Det -> Communication Data
            List<Object> phoneList = new List<Object>();
            if (payer.Phone != null) {
                phoneList.add(new Map<String, Object>{
                    'country_code' => payer.BillingCountry,
                    'standard' => 'X',
                    'telephone' => payer.Phone
                });
            }
            Map<String, Object> communicationData = new Map<String, Object>{
                'phone' => phoneList
            };

            // Build Payer Det -> Company Data
            List<Object> companyData = new List<Object>();
            if (payer.company_code__c != null) {
                companyData.add(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'company_code' => payer.company_code__c
                    }
                });
            }

            // Build Payer Det -> Payment Cards
            List<Object> paymentCardsList = new List<Object>();
            for (Payment_Method__c c : cards) {
                String validFromStr = '';
                String validToStr = '';
                
                if (c.Valid_From__c != null) {
                    Datetime dtFrom = Datetime.newInstance(c.Valid_From__c.year(), c.Valid_From__c.month(), c.Valid_From__c.day());
                    validFromStr = dtFrom.format('MM-dd-yyyy');
                }
                if (c.Valid_To__c != null) {
                    Datetime dtTo = Datetime.newInstance(c.Valid_To__c.year(), c.Valid_To__c.month(), c.Valid_To__c.day());
                    validToStr = dtTo.format('MM-dd-yyyy');
                }

                paymentCardsList.add(new Map<String, Object>{
                    'payment_card_type' => c.Card_Type__c,
                    'payment_card_token' => c.Card_Token__c,
                    'payment_card_name' => c.Cardholder_Name__c,
                    'valid_from' => validFromStr,
                    'valid_to' => validToStr,
                    'default' => c.Is_Default__c ? 'X' : '',
                    'last_four' => c.Last_Four__c
                });
            }

            // Build Payer Det -> SoldTo List
            List<Object> soldToList = new List<Object>();
            for (Account child : soldTos) {
                soldToList.add(new Map<String, Object>{
                    'customer_number' => child.AccountNumber,
                    'sales_area_data' => new Map<String, Object>{
                        'sales_organization' => child.sales_organization__c != null ? child.sales_organization__c : payer.sales_organization__c,
                        'distribution_channel' => child.distribution_channel__c != null ? child.distribution_channel__c : payer.distribution_channel__c,
                        'division' => child.division__c != null ? child.division__c : payer.division__c
                    },
                    'address_data' => new Map<String, Object>{
                        'name' => child.Name,
                        'city' => child.BillingCity,
                        'street' => child.BillingStreet,
                        'postal_code_city' => child.BillingPostalCode,
                        'region' => child.BillingState,
                        'country' => child.BillingCountry
                    }
                });
            }

            // Build Payer Det -> Auto Pay Status
            List<Object> autoPayList = new List<Object>();
            for (Auto_Pay_Enrollment__c ap : autoPays) {
                autoPayList.add(new Map<String, Object>{
                    'company_code' => ap.Company_Code__c,
                    'payment_method' => ap.Payment_Type__c,
                    'enrolled' => ap.Is_Enrolled__c,
                    'payment_card_token' => ap.Payment_Method__r.Card_Token__c
                });
            }

            // Assemble Payer Det
            Map<String, Object> payerDet = new Map<String, Object>{
                'address_data' => addressData,
                'communcation_data' => communicationData,
                'company_data' => companyData,
                'payment_cards' => paymentCardsList,
                'soldto_list' => soldToList,
                'auto_pay_status' => autoPayList
            };

            // Assemble Data Node
            Map<String, Object> dataNode = new Map<String, Object>{
                'application_id' => 'CNBSMV01R',
                'account_id' => payer.account_id__c,
                'user_id' => '000C29F0318A1EDEAFEE896F47D86B81',
                'account_type' => 'Payer',
                'primary_account' => payer.AccountNumber,
                'sales_organization' => payer.sales_organization__c,
                'distribution_channel' => payer.distribution_channel__c,
                'division' => payer.division__c,
                'company_code' => payer.company_code__c,
                'payer_det' => payerDet
            };

            response.put('data', new List<Object>{ dataNode });

            response.put('status', new Map<String, Object>{
                'message_type' => 'S',
                'message_identification' => '/CNBS/X_API',
                'message_number' => 10,
                'message_line_string' => 'Request successfully processed'
            });

        } catch (Exception e) {
            response.put('status', new Map<String, Object>{
                'message_type' => 'E',
                'message_identification' => '/CNBS/X_API',
                'message_number' => 500,
                'message_line_string' => e.getMessage()
            });
        }
        
        if (res != null) {
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(response));
        }
    }
}