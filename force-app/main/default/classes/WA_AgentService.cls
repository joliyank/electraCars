public with sharing class WA_AgentService {

    public class AIResponse {
        public String reply;
        public Map<String, Object> data;
        public Boolean complete;
    }

    public static AIResponse process(
        String userMsg,
        Map<String, Object> data,
        Boolean isExisting,
        String customerName,
        String address,
        String zip
    ){

        try {
            // 🔹 Inject existing customer data (read-only)
            if(isExisting) {
                if(!data.containsKey('address') && address != null) {
                    data.put('address', address);
                }
                if(!data.containsKey('zip') && zip != null) {
                    data.put('zip', zip);
                }
            }
            String prompt = buildPrompt(userMsg, data, isExisting, customerName);

            Http http = new Http();
            HttpRequest req = new HttpRequest();

            req.setEndpoint('callout:Einstein_GPT_API');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');

            req.setBody(JSON.serialize(new Map<String, Object>{
                'prompt' => prompt,
                'temperature' => 0.2
            }));

            HttpResponse res = http.send(req);

            if(res.getStatusCode() != 200) {
                throw new CalloutException(res.getBody());
            }

            Map<String, Object> result =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            String raw = String.valueOf(result.get('text'));

            return parseResponse(raw);

        } catch(Exception e) {
            System.debug('@@ AI ERROR: ' + e.getMessage());

            // 🔁 FALLBACK
            WA_AIService.AIResponse fallback = WA_AIService.process(userMsg, data, isExisting, customerName);
            
            if(fallback == null) {
                AIResponse res = new AIResponse();
                res.reply = 'Sorry, something went wrong. Please try again.';
                res.data = data;
                res.complete = false;
                return res;
            }
        
            AIResponse res = new AIResponse();
            res.reply = fallback.reply;
            res.data = fallback.data;
            res.complete = fallback.complete;
            
            return res;
        }
    }

    private static String buildPrompt(
        String userMsg,
        Map<String, Object> data,
        Boolean isExisting,
        String name
    ) {

        String jsonData = JSON.serialize(data);

        return 'You are an AI assistant for Electra Cars...\n\n' +
               'Existing customer: ' + isExisting + '\n' +
               'Customer name: ' + name + '\n\n' +
               'Already collected data:\n' + jsonData + '\n\n' +
               'User message:\n' + userMsg;
    }

    private static AIResponse parseResponse(String raw) {

        raw = raw.replace('```json', '').replace('```', '').trim();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(raw);

        AIResponse res = new AIResponse();
        res.reply = (String) parsed.get('reply');
        res.data = (Map<String, Object>) parsed.get('data');
        res.complete = (Boolean) parsed.get('complete');

        return res;
    }
}