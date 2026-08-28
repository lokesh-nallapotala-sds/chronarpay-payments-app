@RestResource(urlMapping='/customizing/*')
/**
 * REST API exposing CNBS customizing metadata with the documented response contract.
 */
global with sharing class CustomizingAPI {

    /**
     * Returns the CNBS customizing payload documented for the GET customizing API.
     */
    @HttpGet
    global static void getCustomizingData() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        String apiId = req != null ? req.params.get('apiid') : null;
        if (String.isBlank(apiId)) {
            apiId = 'CNBSMV01R';
        }

        Map<String, Object> response = buildPayload(apiId);

        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    private static Map<String, Object> buildPayload(String apiId) {
        Map<String, Object> payload = new Map<String, Object>();

        payload.put('status', new Map<String, Object>{
            'message_type' => 'S',
            'message_identification' => '/CNBS/X_API',
            'message_number' => 10,
            'message_line_string' => 'Request successfully processed'
        });

        payload.put('release_information', new Map<String, Object>{
            'releae_version' => '14',
            'service_pack' => '00',
            'publishing_date' => '20250321'
        });

        payload.put('sapcust', new Map<String, Object>{
            'currency_decimals' => new List<Object>{
                new Map<String, Object>{'currkey' => '0'},
                new Map<String, Object>{'currkey' => '1', 'currdec' => 1},
                new Map<String, Object>{'currkey' => '2', 'currdec' => 2},
                new Map<String, Object>{'currkey' => '3', 'currdec' => 3},
                new Map<String, Object>{'currkey' => '4', 'currdec' => 4},
                new Map<String, Object>{'currkey' => '5', 'currdec' => 5},
                new Map<String, Object>{'currkey' => '6', 'currdec' => 6},
                new Map<String, Object>{'currkey' => '7', 'currdec' => 7},
                new Map<String, Object>{'currkey' => '8', 'currdec' => 8},
                new Map<String, Object>{'currkey' => '9', 'currdec' => 9},
                new Map<String, Object>{'currkey' => '10', 'currdec' => 10},
                new Map<String, Object>{'currkey' => '11', 'currdec' => 11},
                new Map<String, Object>{'currkey' => '12', 'currdec' => 12},
                new Map<String, Object>{'currkey' => '13', 'currdec' => 13},
                new Map<String, Object>{'currkey' => '14', 'currdec' => 14},
                new Map<String, Object>{'currkey' => 'BEF'},
                new Map<String, Object>{'currkey' => 'ESP'},
                new Map<String, Object>{'currkey' => 'HUF'},
                new Map<String, Object>{'currkey' => 'IDR'},
                new Map<String, Object>{'currkey' => 'ITL'},
                new Map<String, Object>{'currkey' => 'JPY'},
                new Map<String, Object>{'currkey' => 'KRW'},
                new Map<String, Object>{'currkey' => 'KUD', 'currdec' => 3},
                new Map<String, Object>{'currkey' => 'LUF'},
                new Map<String, Object>{'currkey' => 'PKT', 'currdec' => 3},
                new Map<String, Object>{'currkey' => 'RUR'},
                new Map<String, Object>{'currkey' => 'TJLP', 'currdec' => 5},
                new Map<String, Object>{'currkey' => 'TND', 'currdec' => 3},
                new Map<String, Object>{'currkey' => 'TWD'},
                new Map<String, Object>{'currkey' => 'USD5', 'currdec' => 5},
                new Map<String, Object>{'currkey' => 'USDN', 'currdec' => 5}
            }
        });

        payload.put('logging_events', new List<Object>{
            new Map<String, Object>{
                'id' => 'ADD_PAYMENT_CARD',
                'description' => 'Add payment card'
            },
            new Map<String, Object>{
                'id' => 'DEL_PAYMENT_CARD',
                'description' => 'Delete payment card'
            },
            new Map<String, Object>{
                'id' => 'MOD_PAYMENT_CARD',
                'description' => 'Modify payment card'
            },
            new Map<String, Object>{
                'id' => 'POST_DEPOSIT',
                'description' => 'Pay deposit'
            },
            new Map<String, Object>{
                'id' => 'POST_INVOICE',
                'description' => 'Pay Invoice'
            }
        });

        payload.put('parameters', new List<Object>{
            new Map<String, Object>{
                'parameter_name' => 'AVSDEV',
                'parameter_value' => '{"domain":"https://cert-xipayapi.worldpay.com/pmxigge/xipay30ws.asmx", "password":"Qsi8790*", "username":"WSAQSIDV"}'
            }
        });

        payload.put('function_modules', new List<Object>{
            new Map<String, Object>{
                'function_module_name' => 'Z_CNBS_API_EXA1_ROUTE_BOOK'
            }
        });

        payload.put('payment_cards', new List<Object>{
            new Map<String, Object>{
                'payment_provider' => 'PM',
                'payment_card_type' => 'AMEX',
                'external_payment_card_type' => '3000'
            },
            new Map<String, Object>{
                'payment_provider' => 'PM',
                'payment_card_type' => 'EC'
            },
            new Map<String, Object>{
                'payment_provider' => 'PM',
                'payment_card_type' => 'MC',
                'external_payment_card_type' => '5000'
            },
            new Map<String, Object>{
                'payment_provider' => 'PM',
                'payment_card_type' => 'VISA',
                'external_payment_card_type' => '4000',
                'preauthorization_active' => 'X',
                'preauthorization_amount' => 0.1
            }
        });
            payload.put('payment_reason_codes', new List<Object>{
            new Map<String, Object>{
                'company_code' => '3000',
                'payment_type' => 'D',
                'reason_code' => '055',
                'description' => 'Payment on Account'
            },
            new Map<String, Object>{
                'company_code' => '3000',
                'payment_type' => 'O',
                'reason_code' => 'DG',
                'comments_required' => 'X',
                'description' => 'Damaged goods'
            },
            new Map<String, Object>{
                'company_code' => '3000',
                'payment_type' => 'O',
                'reason_code' => 'PP',
                'description' => 'Partial payment'
            },
            new Map<String, Object>{
                'company_code' => '5000',
                'payment_type' => 'O',
                'reason_code' => 'SP',
                'description' => 'Partial payment'
            }
        });

        payload.put('payment_provider', new List<Object>{
            new Map<String, Object>{
                'payment_provider' => 'PM',
                'description' => 'Worldpay',
                'payment_provider_key' => '6w/XoN9?7i}B-2Gn8y!Fg%W45Cd+j3*R',
                'payment_provider_merchant_guide' => '711c8483-d37f-4d82-bb9d-0273a560a96d',
                'payment_provider_version' => 'PM03',
                'secure_3ds_enabled' => 'X',
                'secure_3ds_version' => '2.2.0',
                'initialization_url' => 'https://cert-xiecomm.worldpay.com/DIeComm'
            }
        });

        payload.put('payment_methodes', new List<Object>{
            new Map<String, Object>{
                'payment_type' => 'D',
                'payment_method' => 'CC',
                'description' => 'Credit Card',
                'active' => 'X'
            },
            new Map<String, Object>{
                'payment_type' => 'D',
                'payment_method' => 'EC',
                'description' => 'E-Check',
                'active' => 'X'
            },
            new Map<String, Object>{
                'payment_type' => 'O',
                'payment_method' => 'CC',
                'description' => 'Credit Card',
                'active' => 'X'
            },
            new Map<String, Object>{
                'payment_type' => 'O',
                'payment_method' => 'EC',
                'description' => 'E-Check',
                'active' => 'X'
            }
        });

        payload.put('payment_types', new List<Object>{
            new Map<String, Object>{
                'payment_type' => 'D',
                'description' => '[Deposits] Direct AR',
                'active' => 'X'
            },
            new Map<String, Object>{
                'payment_type' => 'O',
                'description' => '[Payments] Open AR',
                'active' => 'X',
                'overpayment_allowed' => 'X',
                'reason_not_required' => 'X'
            }
        });

        payload.put('document_status', new List<Object>{
            new Map<String, Object>{
                'status_id' => '01',
                'status' => '01',
                'description' => 'Open'
            },
            new Map<String, Object>{
                'status_id' => '01',
                'status' => '02',
                'description' => 'Completed'
            },
            new Map<String, Object>{
                'status_id' => '01',
                'status' => '03',
                'description' => 'Open and Completed'
            }
        });

        payload.put('document_types', new List<Object>{
            new Map<String, Object>{
                'document_type' => '01',
                'description' => 'Invoice',
                'trtyp' => '01',
                'maximum_documents_returned' => 500,
                'pdf_document_available' => 'X',
                'status_id' => '01'
            },
            new Map<String, Object>{
                'document_type' => '02',
                'description' => 'Payments',
                'trtyp' => '02',
                'maximum_documents_returned' => 500,
                'pdf_document_available' => 'X',
                'status_id' => '02'
            }
        });

        payload.put('sales_area_data', new List<Object>{
            new Map<String, Object>{
                'sales_organization' => '3000',
                'distribution_channel' => '10',
                'division' => '00',
                'active' => 'X'
            },
            new Map<String, Object>{
                'sales_organization' => '5000',
                'distribution_channel' => '14',
                'division' => '00',
                'active' => 'X'
            }
        });

        payload.put('company_codes', new List<Object>{
            new Map<String, Object>{
                'company_code' => '3000',
                'currency_key' => 'USD',
                'active' => 'X',
                'enable_deposits' => 'X',
                'enable_echeck' => 'X',
                'enable_schedule_payments' => 'X',
                'enable_auto_pay' => 'X'
            },
            new Map<String, Object>{
                'company_code' => '5000',
                'currency_key' => 'JPY',
                'active' => 'X',
                'enable_deposits' => 'X',
                'enable_echeck' => 'X',
                'enable_schedule_payments' => 'X',
                'enable_auto_pay' => 'X'
            }
        });

        payload.put('general_data', new Map<String, Object>{
            'partial_payments_allowed' => 'X',
            'cvv_use_control' => '1'
        });

        payload.put('regional_format', 'US');
        payload.put('password_reset_delta', 60);
        payload.put('maximum_failed_login_count', 5);
        payload.put('sap_system_type', 'D');
        payload.put('description', 'CNBS API Master V01 (RESTful)');
        payload.put('application_id', apiId);
        return payload;
    }
}