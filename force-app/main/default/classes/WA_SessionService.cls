/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-18-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class WA_SessionService {

    public class SessionResult {
        public WhatsApp_Session__c session;
        public Map<String, Object> data;
    }

    public static SessionResult getOrCreateSession(String phone, Id customerId) {

        List<WhatsApp_Session__c> sessions = [
            SELECT Id, Collected_Data__c, Status__c, Test_Drive__c, Customer__c
            FROM WhatsApp_Session__c
            WHERE Phone__c = :phone
            AND Status__c = 'Active'
            LIMIT 1
        ];

        WhatsApp_Session__c session;

        if(!sessions.isEmpty()) {
            session = sessions[0];
        } else {
            session = new WhatsApp_Session__c(
                Phone__c = phone,
                Customer__c = customerId,
                Status__c = 'Active',
                Session_Start_Time__c = System.now(),
                Last_Interaction_Time__c = System.now()
            );
            insert session;
        }

        SessionResult result = new SessionResult();
        result.session = session;
        result.data = WA_JsonUtil.parse(session.Collected_Data__c);

        return result;
    }

    public static void updateSession(
        WhatsApp_Session__c session,
        Map<String, Object> data,
        String userMsg,
        String aiReply,
        Boolean isComplete
    ) {
        session.Collected_Data__c = WA_JsonUtil.stringify(data);
        session.Last_User_Message__c = userMsg;
        session.Last_AI_Response__c = aiReply;
        session.Last_Interaction_Time__c = System.now();
        session.Is_Complete__c = isComplete;

        if(isComplete) {
            session.Status__c = 'Completed';
        }

        update session;
    }
}