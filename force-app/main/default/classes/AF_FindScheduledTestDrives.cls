public with sharing class AF_FindScheduledTestDrives {

    // ===== INPUT =====
    public class Input {
        @InvocableVariable(required=false description='Customer mobile number (digits preferred)')
        public String mobileNumber;

        @InvocableVariable(required=false description='Test Drive booking number (Test_Drive__c.Name, auto-number)')
        public String testDriveName;
    }

    // ===== OUTPUT =====
    public class Output {
        @InvocableVariable(description='True if at least one scheduled test drive is found')
        public Boolean hasMatches;

        @InvocableVariable(description='True if more than one scheduled booking is found')
        public Boolean hasMultiple;

        @InvocableVariable(description='List of matching Test Drive record Ids')
        public List<String> testDriveIds;

        @InvocableVariable(description='List of matching Test Drive booking numbers (Name)')
        public List<String> testDriveNames;

        @InvocableVariable(description='Numbered options text to display exactly as-is')
        public String bookingOptionsText;

        @InvocableVariable(description='Message for the agent')
        public String message;
    }

    @InvocableMethod(
        label='Find Scheduled Test Drives'
        description='Find scheduled test drives by mobile number or booking number (Name). Returns only Status__c = Scheduled.'
    )
    public static List<Output> find(List<Input> requests) {

        Output out = initOutput();

        try {
            // Guard: No input
            if (requests == null || requests.isEmpty() || requests[0] == null) {
                out.message = 'No input received.';
                return new List<Output>{ out };
            }

            Input req = requests[0];

            // Raw inputs as agent may map them incorrectly
            String rawMobile = req.mobileNumber;
            String rawName   = req.testDriveName;

            // ---------------------------
            // SELF-HEAL / AUTO-DETECT
            // ---------------------------
            // If mobileNumber contains non-digits (letters/hyphen), assume it's actually booking number (ex: TR-0028).
            if (String.isNotBlank(rawMobile) && String.isBlank(rawName)) {
                String m = rawMobile.trim();
                String nonDigits = m.replaceAll('[0-9]', '');
                if (m.contains('-') || nonDigits.length() > 0) {
                    rawName = m;
                    rawMobile = null;
                }
            }

            // If testDriveName looks like a 10+ digit number, assume it's actually a mobile number.
            if (String.isNotBlank(rawName) && String.isBlank(rawMobile)) {
                String digitsFromName = rawName.replaceAll('[^0-9]', '');
                if (digitsFromName != null && digitsFromName.length() >= 10) {
                    rawMobile = rawName;
                    rawName = null;
                }
            }

            String nameKey = normalizeName(rawName);
            String mobile  = normalizeMobile(rawMobile);

            // Must have at least one identifier
            if (String.isBlank(nameKey) && String.isBlank(mobile)) {
                out.message = 'Provide either a 10-digit mobile number or booking number (example: TR-0028).';
                return new List<Output>{ out };
            }

            List<Test_Drive__c> tds = new List<Test_Drive__c>();

            if (String.isNotBlank(nameKey)) {
                // Booking number path (exact match)
                tds = [
                    SELECT Id, Name, Status__c, Test_Drive_Date_Time__c, Mobile_Number__c,
                           Dealer__r.Name, Vehicle__r.Name, Test_Drive_Location__c
                    FROM Test_Drive__c
                    WHERE Name = :nameKey
                      AND Status__c = 'Scheduled'
                    LIMIT 10
                ];
            } else {
                // Mobile path (Mobile_Number__c is a Number/Decimal field)
                Decimal mobileDec;
                try {
                    mobileDec = Decimal.valueOf(mobile);
                } catch (Exception e) {
                    out.message = 'Invalid mobile number format. Please share a 10-digit mobile number.';
                    return new List<Output>{ out };
                }

                tds = [
                    SELECT Id, Name, Status__c, Test_Drive_Date_Time__c, Mobile_Number__c,
                           Dealer__r.Name, Vehicle__r.Name, Test_Drive_Location__c
                    FROM Test_Drive__c
                    WHERE Mobile_Number__c = :mobileDec
                      AND Status__c = 'Scheduled'
                    ORDER BY Test_Drive_Date_Time__c DESC
                    LIMIT 10
                ];
            }

            if (tds.isEmpty()) {
                out.hasMatches = false;
                out.hasMultiple = false;
                out.bookingOptionsText = null;
                out.message = 'No Scheduled bookings found. If you have a booking number, share it (example: TR-0028).';
                return new List<Output>{ out };
            }

            // Build response
            out.hasMatches = true;
            out.hasMultiple = (tds.size() > 1);

            for (Test_Drive__c td : tds) {
                out.testDriveIds.add(String.valueOf(td.Id));
                out.testDriveNames.add(td.Name);
            }

            out.bookingOptionsText = buildOptionsText(tds);
            out.message = out.hasMultiple ? 'Multiple Scheduled bookings found.' : 'One Scheduled booking found.';
            return new List<Output>{ out };

        } catch (Exception ex) {
            // IMPORTANT: never bubble exceptions to Agentforce (prevents "session ended, contact admin")
            out.hasMatches = false;
            out.hasMultiple = false;
            out.bookingOptionsText = null;
            out.message = 'Unable to check bookings due to an internal error. Please try again or share your booking number (example: TR-0028).';
            return new List<Output>{ out };
        }
    }

    // ===== Helpers =====
    private static Output initOutput() {
        Output out = new Output();
        out.hasMatches = false;
        out.hasMultiple = false;
        out.testDriveIds = new List<String>();
        out.testDriveNames = new List<String>();
        out.bookingOptionsText = null;
        out.message = null;
        return out;
    }

    private static String normalizeMobile(String mobile) {
        if (String.isBlank(mobile)) return null;
        String digits = mobile.replaceAll('[^0-9]', '');
        // Keep last 10 digits if user types country code
        if (digits != null && digits.length() > 10) {
            digits = digits.substring(digits.length() - 10);
        }
        return digits;
    }

    private static String normalizeName(String nameVal) {
        if (String.isBlank(nameVal)) return null;
        // Keep hyphen (TR-0028), remove only spaces
        String n = nameVal.trim();
        n = n.replaceAll('\\s+', '');
        return n;
    }

    private static String buildOptionsText(List<Test_Drive__c> tds) {
        List<String> lines = new List<String>();
        Integer idx = 1;

        for (Test_Drive__c td : tds) {
            String dt = (td.Test_Drive_Date_Time__c == null) ? 'N/A' : td.Test_Drive_Date_Time__c.format();
            String dealer = (td.Dealer__r == null) ? 'N/A' : td.Dealer__r.Name;
            String vehicle = (td.Vehicle__r == null) ? 'N/A' : td.Vehicle__r.Name;
            String loc = String.isBlank(td.Test_Drive_Location__c) ? 'N/A' : td.Test_Drive_Location__c;

            lines.add(idx + ') ' + td.Name + ' | ' + dt + ' | ' + vehicle + ' | ' + dealer + ' | ' + loc);
            idx++;
        }
        return String.join(lines, '\n');
    }
}