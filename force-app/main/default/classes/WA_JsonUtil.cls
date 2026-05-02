public class WA_JsonUtil {

    public static Map<String, Object> parse(String jsonStr) {
        if(String.isBlank(jsonStr)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
    }

    public static String stringify(Map<String, Object> data) {
        if(data == null) {
            data = new Map<String, Object>();
        }
        return JSON.serialize(data);
    }

    public static String getString(Map<String, Object> data, String key) {
        if(data.containsKey(key) && data.get(key) != null) {
            return String.valueOf(data.get(key));
        }
        return null;
    }

    public static void put(Map<String, Object> data, String key, Object value) {
        if(value != null) {
            data.put(key, value);
        }
    }
}