public with sharing class AF_UpsertLeadByMobile {

    // ===== INPUT =====
    public class Input {
        @InvocableVariable(required=true description='Customer mobile number (digits preferred)')
        public String mobileNumber;

        @InvocableVariable(required=false description='Customer name ONLY if user explicitly provided it')
        public String customerName;

        // NEW: dealer chosen by ZIP step (Account Id)
        @InvocableVariable(required=false description='Selected dealer Account Id to stamp on Lead.Dealership__c')
        public Id dealerId;

    }

    // ===== OUTPUT =====
    public class Output {
        @InvocableVariable(description='Lead Id created or found (String)')
        public String leadId;

        @InvocableVariable(description='True if an existing Lead was found')
        public Boolean isExisting;

        @InvocableVariable(description='Customer name from existing Lead or created Lead')
        public String customerName;

        @InvocableVariable(description='True if Lead not found and customerName is required to create')
        public Boolean needsCustomerName;

        @InvocableVariable(description='Message for the agent to use (not for user unless needed)')
        public String message;
    }

    @InvocableMethod(
        label='Find or Create Lead by Mobile'
        description='Find existing Lead by normalized mobile. If not found and no valid name provided, returns needsCustomerName=true and no leadId. If valid name provided, creates Lead and returns leadId.'
    )
    public static List<Output> upsertLead(List<Input> requests) {

        Output out = initOutput();

        if (requests == null || requests.isEmpty()) {
            out.message = 'No input received.';
            return new List<Output>{ out };
        }

        Input req = requests[0];
        String mobile = normalizeMobile(req.mobileNumber);

        if (String.isBlank(mobile)) {
            out.message = 'Mobile number is blank/invalid.';
            return new List<Output>{ out };
        }

        // Try to match both MobilePhone and Phone for safety
        // (Useful if legacy data stored in Phone, or older integrations used Phone)
        List<Lead> existingLeads = [
            SELECT Id, FirstName, LastName, MobilePhone, Phone, Dealership__c
            FROM Lead
            WHERE MobilePhone = :mobile OR Phone = :mobile
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (!existingLeads.isEmpty()) {
            Lead l = existingLeads[0];
            out.leadId = String.valueOf(l.Id);
            out.isExisting = true;
            out.customerName = buildName(l.FirstName, l.LastName);
            out.message = 'Existing lead found.';
            return new List<Output>{ out };
        }

        // Not found -> MUST require a real name before creating
        String nameVal = sanitizeName(req.customerName);
        if (String.isBlank(nameVal)) {
            out.needsCustomerName = true;
            out.message = 'Lead not found. Customer name is required to create a new Lead.';
            return new List<Output>{ out };
        }

        // Create new Lead only when valid name provided
        Lead newLead = new Lead();
        newLead.MobilePhone = mobile;
        newLead.LastName = trim80(nameVal);
        newLead.Company = 'Individual';
        newLead.Status = 'Open - Not Contacted';
        newLead.For_Test_Drive__c = true;
        // NEW: stamp dealership
        if (req.dealerId != null) {
            newLead.Dealership__c = req.dealerId;
        }

        insert newLead;

        out.leadId = String.valueOf(newLead.Id);
        out.isExisting = false;
        out.customerName = newLead.LastName;
        out.needsCustomerName = false;
        out.message = 'New lead created.';
        return new List<Output>{ out };
    }

    // ===== Helpers =====

    private static Output initOutput() {
        Output out = new Output();
        out.leadId = null;
        out.isExisting = false;
        out.customerName = null;
        out.needsCustomerName = false;
        out.message = null;
        return out;
    }

    private static String normalizeMobile(String mobile) {
        if (String.isBlank(mobile)) return null;
        String digits = mobile.replaceAll('[^0-9]', '');
        // India-friendly: keep last 10 digits if user typed country code
        if (digits != null && digits.length() > 10) {
            digits = digits.substring(digits.length() - 10);
        }
        return digits;
    }

    // Ensures agent cannot pass placeholders and accidentally create leads
    private static String sanitizeName(String nameVal) {
        if (String.isBlank(nameVal)) return null;
        String n = nameVal.trim();
        String low = n.toLowerCase();

        Set<String> invalid = new Set<String>{
            'na', 'n/a', 'none', 'unknown', 'visitor', 'customer', 'test', '-', '--'
        };
        if (invalid.contains(low)) return null;

        return n;
    }

    private static String trim80(String s) {
        if (String.isBlank(s)) return s;
        s = s.trim();
        return s.length() > 80 ? s.substring(0, 80) : s;
    }

    private static String buildName(String firstName, String lastName) {
        if (String.isBlank(firstName)) return lastName;
        if (String.isBlank(lastName)) return firstName;
        return firstName + ' ' + lastName;
    }
}