@RestResource(urlMapping='/changePassword/*')
global with sharing class ChangePasswordAPI {

    @HttpPost
    global static void changePassword() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', 'Request body is required'))));
                return;
            }

            Map<String, Object> requestMap = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            String currentPassword = getStringValue(requestMap, 'current_password');
            String newPassword = getStringValue(requestMap, 'new_password');
            String userId = getUserIdFromUrl(req);

            if (String.isBlank(newPassword)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', 'new_password is required'))));
                return;
            }

            if (String.isBlank(currentPassword)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', 'current_password is required'))));
                return;
            }

            if (String.isBlank(userId)) {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', 'user_id is required in URL'))));
                return;
            }

            List<Chronarpay_User__c> targetUsers = [
                SELECT Id, Name, Status__c, Salt__c, Hash__c
                FROM Chronarpay_User__c
                WHERE Id = :userId
                LIMIT 1
            ];

            if (targetUsers.isEmpty()) {
                res.statusCode = 404;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', 'User not found'))));
                return;
            }

            //System.setPassword(targetUsers[0].Id, newPassword);
            String currentPasswordHash = EncodingUtil.base64Encode(Crypto.generateDigest('SHA-256', Blob.valueOf(targetUsers[0].Salt__c + currentPassword)));
            if(currentPasswordHash == targetUsers[0].Hash__c) {
                String salt = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
                String hash = EncodingUtil.base64Encode(Crypto.generateDigest('SHA-256', Blob.valueOf(salt + newPassword)));
                
                targetUsers[0].Salt__c = salt;
                targetUsers[0].Hash__c = hash;
                update targetUsers[0];
                
                res.statusCode = 200;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('S', 'Password changed successfully'))));
            } else {
                res.statusCode = 400;
                res.addHeader('Content-Type', 'application/json');
                res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', 'Current password is Wrong'))));
            }
        } catch (Exception e) {
            res.statusCode = 500;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new ApiResponse(new List<PasswordChangeResponse>(), buildStatusResponse('E', e.getMessage()))));
        }
    }

    private static String getStringValue(Map<String, Object> requestMap, String key) {
        if (requestMap == null || !requestMap.containsKey(key)) {
            return null;
        }
        Object value = requestMap.get(key);
        return value == null ? null : String.valueOf(value);
    }

    private static String getUserIdFromUrl(RestRequest req) {
        if (req == null) {
            return null;
        }

        if (req.params != null) {
            String userIdFromParam = req.params.get('userId');
            if (String.isBlank(userIdFromParam)) {
                userIdFromParam = req.params.get('user_id');
            }
            if (String.isNotBlank(userIdFromParam)) {
                return userIdFromParam;
            }
        }

        if (req.requestURI == null) {
            return null;
        }

        String requestUri = req.requestURI;
        if (requestUri.contains('?')) {
            requestUri = requestUri.substringBefore('?');
        }
        if (requestUri.endsWith('/')) {
            requestUri = requestUri.substring(0, requestUri.length() - 1);
        }

        Integer lastSlash = requestUri.lastIndexOf('/');
        if (lastSlash < 0) {
            return null;
        }

        return requestUri.substring(lastSlash + 1);
    }

    private static StatusResponse buildStatusResponse(String messageType, String messageLineString) {
        return new StatusResponse(messageType, '/CNBS/X_API', 10, messageLineString);
    }

    global class ApiResponse {
        public List<PasswordChangeResponse> data;
        public StatusResponse status;

        public ApiResponse(List<PasswordChangeResponse> dataList, StatusResponse statusResponse) {
            data = dataList;
            status = statusResponse;
        }
    }

    global class PasswordChangeResponse {
        public String user_id;
        public String username;
    }

    global class StatusResponse {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;

        public StatusResponse(String messageType, String messageIdentification, Integer messageNumber, String messageLineString) {
            message_type = messageType;
            message_identification = messageIdentification;
            message_number = messageNumber;
            message_line_string = messageLineString;
        }
    }
}