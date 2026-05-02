/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-19-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@RestResource(urlMapping='/whatsapp')
global without sharing class WA_Webhook {

    @HttpPost
    global static void handleWebhook() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {

            Map<String, String> params = req.params;

            String message = params.get('Body');
            String phone = params.get('From');

            if(String.isBlank(phone)) {
                sendResponse(res, 'Missing phone parameter');
                return;
            }

            phone = phone.replace('whatsapp:', '').trim();
            if(phone.length() > 10) {
                phone = phone.right(10);
            }

            // 🔹 STEP 1: Find Customer
            Customer__c customer;
            Boolean isExistingCustomer = false;

            List<Customer__c> custList = [
                SELECT Id, Name
                FROM Customer__c
                WHERE Phone__c LIKE :('%' + phone)
                LIMIT 1
            ];

            if(!custList.isEmpty()) {
                customer = custList[0];
                isExistingCustomer = true;
            }

            // 🔹 STEP 2: Session
            WA_SessionService.SessionResult sessionRes =
                WA_SessionService.getOrCreateSession(phone, customer != null ? customer.Id : null);

            // 🔹 STEP 3: AI
            // WA_AIService.AIResponse aiRes =
            //     WA_AIService.process(message, sessionRes.data, isExistingCustomer, customer != null ? customer.Name : null);

            WA_AgentService.AIResponse aiRes = WA_AgentService.process(
                                                message,
                                                sessionRes.data,
                                                isExistingCustomer,
                                                customer != null ? customer.Name : null,
                                                customer != null ? customer.Address__c : null,
                                                customer != null ? customer.Zip_Code__c : null
                                            );

            // 🔹 STEP 4: Create Lead (only once when name captured)
            if(!isExistingCustomer &&
               sessionRes.data.containsKey('name') &&
               !sessionRes.data.containsKey('leadCreated')) {

                Lead l = new Lead(
                    LastName = String.valueOf(sessionRes.data.get('name')),
                    MobilePhone = phone
                );
                insert l;

                sessionRes.data.put('leadCreated', true);
            }

            // 🔹 STEP 5: Update Session
            WA_SessionService.updateSession(
                sessionRes.session,
                aiRes.data,
                message,
                aiRes.reply,
                aiRes.complete
            );

            // 🔹 STEP 6: Create Customer + Test Drive
            if(aiRes.complete && aiRes.data.get('confirmed') == true && sessionRes.session.Test_Drive__c == null) {

                if(!isExistingCustomer) {
                    customer = new Customer__c(
                        Name = String.valueOf(aiRes.data.get('name')),
                        Phone__c = phone,
                        Cust_Zip_Code__c = String.valueOf(aiRes.data.get('zip'))
                    );
                    insert customer;
                }

                Test_Drive__c td = new Test_Drive__c(
                    Customer__c = customer.Id,
                    Model__c = String.valueOf(aiRes.data.get('model')),
                    Zip_Code__c = String.valueOf(aiRes.data.get('zip'))
                );

                insert td;

                sessionRes.session.Test_Drive__c = td.Id;
                sessionRes.session.Customer__c = customer.Id;
                update sessionRes.session;
            }

            sendResponse(res, aiRes.reply);

        } catch(Exception e) {
            System.debug('@@ ERROR: ' + e.getMessage());
            sendResponse(res, 'Something went wrong. Please try again.');
        }
    }

    private static void sendResponse(RestResponse res, String message) {

        if(String.isBlank(message)) {
            message = 'Sorry, I did not understand that.';
        }

        message = escapeXml(message);

        String xmlResponse =
            '<Response><Message>' +
            message +
            '</Message></Response>';

        res.responseBody = Blob.valueOf(xmlResponse);
        res.addHeader('Content-Type', 'text/xml');
    }

    private static String escapeXml(String input) {

        if(input == null) return '';

        input = input.replace('&', '&amp;');
        input = input.replace('<', '&lt;');
        input = input.replace('>', '&gt;');
        input = input.replace('"', '&quot;');
        input = input.replace('\'', '&apos;');

        return input;
    }
}