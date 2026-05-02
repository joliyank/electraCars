/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-18-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public class WA_AIService {

    public class AIResponse {
        public String reply;
        public Map<String, Object> data;
        public Boolean complete;
    }

    public static AIResponse process(String userMsg, Map<String, Object> data, Boolean isExistingCustomer, String customerName) {

        AIResponse res = new AIResponse();
        res.data = data;

        String msg = userMsg != null ? userMsg.toLowerCase().trim() : '';

        // 🔹 NEW USER → Ask Name First
        if(!isExistingCustomer && !data.containsKey('name')) {

            if(msg == 'hi' || msg == 'hello' || msg.length() < 2) {
                res.reply = 'Hi 👋 Welcome to Electra Cars! May I know your name?';
                res.complete = false;
                return res;
            }

            data.put('name', userMsg);
            res.reply = 'Nice to meet you ' + userMsg + '! Which car model would you like to test drive?';
            res.complete = false;
            return res;
        }

        // 🔹 Existing user greeting
        if(isExistingCustomer && data.isEmpty() && (msg == 'hi' || msg == 'hello')) {
            String name = String.isBlank(customerName) ? '' : ' ' + customerName;
            res.reply = 'Welcome back' + name + '! Which car model would you like to test drive?';
            res.complete = false;
            return res;
        }

        // 🔹 Model
        if(!data.containsKey('model')) {
            data.put('model', userMsg);
            res.reply = 'Great choice! When would you like to schedule the test drive?';
            res.complete = false;
        }
        // 🔹 Date
        else if(!data.containsKey('date')) {
            data.put('date', userMsg);
            res.reply = 'Nice 👍 Please share your ZIP code.';
            res.complete = false;
        }
        // 🔹 Zip
        else if(!data.containsKey('zip')) {
            data.put('zip', userMsg);
            res.reply = '✅ Your test drive is booked!';
            res.complete = true;
        }
        else {
            res.reply = 'Your booking is already completed.';
            res.complete = true;
        }

        return res;
    }
}