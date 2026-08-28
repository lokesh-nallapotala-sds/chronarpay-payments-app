@RestResource(urlMapping='/users/*')
global with sharing class UserAPI {

    @HttpGet
    global static void getUsers() {

        RestResponse res = RestContext.response;

        try {

            List<User> users = [
                SELECT Id,
                       Name,
                       FirstName,
                       LastName,
                       Email,
                       Username,
                       IsActive
                FROM User
                WHERE IsActive = true
                ORDER BY Name
            ];

            List<UserResponse> responseList = new List<UserResponse>();

            for(User u : users){
                UserResponse r = new UserResponse();
                r.id = u.Id;
                r.name = u.Name;
                r.firstName = u.FirstName;
                r.lastName = u.LastName;
                r.email = u.Email;
                r.username = u.Username;
                r.isActive = u.IsActive;
                responseList.add(r);
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(responseList));

        } catch(Exception e){

            res.statusCode = 500;
            res.responseBody = Blob.valueOf(
                JSON.serialize(new ErrorResponse(e.getMessage()))
            );
        }
    }

    global class UserResponse{
        public String id;
        public String name;
        public String firstName;
        public String lastName;
        public String email;
        public String username;
        public Boolean isActive;
    }

    global class ErrorResponse{
        public String message;

        public ErrorResponse(String msg){
            message = msg;
        }
    }
}