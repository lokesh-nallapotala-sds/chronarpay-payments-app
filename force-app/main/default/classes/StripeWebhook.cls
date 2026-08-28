@RestResource(urlMapping='/stripeWebhook/*')
global with sharing class StripeWebhook {

    @HttpPost
    global static void processWebhook() {

        String body =
            RestContext.request.requestBody.toString();

        System.debug('Webhook Body: ' + body);

        // Later we will parse the payment
        // and update SAP or your JSON source.
    }
}