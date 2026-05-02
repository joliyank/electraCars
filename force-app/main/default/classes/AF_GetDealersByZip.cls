public with sharing class AF_GetDealersByZip {

    // ===== INPUT =====
    public class Input {
        @InvocableVariable(required=true description='ZIP code entered by the customer')
        public String zipCode;
    }

    // ===== OUTPUT =====
    public class Output {
        @InvocableVariable public List<Id> dealerIds;
        @InvocableVariable public List<String> dealerNames;
    }

    @InvocableMethod(
        label='Get Dealers by ZIP'
        description='Returns all dealer accounts for a given ZIP code'
    )
    public static List<Output> getDealers(List<Input> requests) {
        String corrId = 'AGENT-' + String.valueOf(Crypto.getRandomLong());
        publishAudit('AF_GetDealersByZip', corrId, 'START', 'Invoked', null);

        system.debug('@@@ inside: ');
        system.debug(LoggingLevel.ERROR,'@@@ : inside 2 '); 
        Output out = new Output();
        out.dealerIds = new List<Id>();
        out.dealerNames = new List<String>();

        if (requests == null || requests.isEmpty()) {
            return new List<Output>{ out };
        }

        String zip = normalizeZip(requests[0].zipCode);
        if (String.isBlank(zip)) {
            return new List<Output>{ out };
        }

        List<Account> dealers = [
            SELECT Id, Name
            FROM Account
            WHERE BillingPostalCode = :zip
            AND RecordType.Name = 'Business Account'
        ];

        for (Account acc : dealers) {
            out.dealerIds.add(acc.Id);
            out.dealerNames.add(acc.Name);
        }

        return new List<Output>{ out };
    }

    private static String normalizeZip(String zip) {
        if (String.isBlank(zip)) return null;
        return zip.replaceAll('[^0-9A-Za-z]', '').trim();
    }

    private static void publishAudit(String actionName, String corrId, String status, String message, String payload) {
        try {
            Agent_Action_Audit__e evt = new Agent_Action_Audit__e();
            evt.ActionName__c = actionName;
            evt.CorrelationId__c = corrId;
            evt.Status__c = status;
            evt.Message__c = message;
            evt.Payload__c = payload;
            EventBus.publish(evt);
        } catch (Exception ignore) {
            system.debug('@@@ inside catch of publishAudit: ');
            
            // Never fail the business transaction because audit failed
        }
    }
}