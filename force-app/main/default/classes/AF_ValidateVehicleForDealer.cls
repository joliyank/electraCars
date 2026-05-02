/* Class 3----------------*/
public with sharing class AF_ValidateVehicleForDealer {

    // ---------- Invocable IO ----------
    public class Input {
        @InvocableVariable(required=true description='Dealer Account Id')
        public Id dealerId;

        @InvocableVariable(required=true description='Vehicle name typed by user (free text)')
        public String vehicleName;

        @InvocableVariable(required=false description='Max results to return (default 5, max 10)')
        public Integer maxResults;
    }

    public class Output {
        @InvocableVariable public Boolean isAvailable;
        @InvocableVariable public Id vehicleId;
        @InvocableVariable public String vehicleNameMatched;

        @InvocableVariable public Boolean needsUserConfirmation; // true when multiple matches need user selection
        @InvocableVariable public Integer matchCount;            // total matches returned (after dealer filtering)
        @InvocableVariable public String vehicleOptionsJson;     // JSON array of options for agent UI
        @InvocableVariable public String message;                // friendly status message
        @InvocableVariable public String vehicleOptionsText;     // numbered list for agent UI
        @InvocableVariable public String optionIdsCsv;           // semicolon-separated IDs aligned by index
        @InvocableVariable public String optionNamesCsv;         // semicolon-separated Names aligned by index
        @InvocableVariable public String optionAvailabilityCsv;  // semicolon-separated true/false aligned by index
    }

    // Non-invocable DTO used inside vehicleOptionsJson
    private class VehicleOptionDTO {
        public Id id;
        public String name;
        public Boolean isAvailable;
        public VehicleOptionDTO(Id id, String name, Boolean isAvailable) {
            this.id = id;
            this.name = name;
            this.isAvailable = isAvailable;
        }
    }

    @InvocableMethod(
        label='Validate Vehicle for Dealer'
        description='Search Vehicle by name (SOSL) and validate test drive availability for the dealer via Dealer_Vehicle__c'
    )
    public static List<Output> validate(List<Input> requests) {
        List<Output> results = new List<Output>();

        if (requests == null || requests.isEmpty()) {
            results.add(buildEmpty('No input received.'));
            return results;
        }

        // Process each request (Invocable bulk-safe)
        for (Input req : requests) {
            Output out = new Output();
            out.isAvailable = false;
            out.needsUserConfirmation = false;
            out.matchCount = 0;
            out.vehicleOptionsJson = '[]';
            out.vehicleOptionsText = '';
            out.optionIdsCsv = '';
            out.optionNamesCsv = '';
            out.optionAvailabilityCsv = '';

            // Basic validation
            if (req == null || req.dealerId == null || String.isBlank(req.vehicleName)) {
                out.message = 'Dealer and vehicle name are required.';
                results.add(out);
                continue;
            }

            Integer lim = (req.maxResults == null) ? 5 : req.maxResults;
            if (lim < 1) lim = 5;
            if (lim > 10) lim = 10;

            String cleaned = normalize(req.vehicleName);
            if (cleaned.length() < 2) {
                out.message = 'Please enter at least 2 characters of the vehicle name.';
                results.add(out);
                continue;
            }

            // -------- 1) SOSL search Vehicles by Name (google-like) --------
            List<Vehicle> vehicles = new List<Vehicle>();
            try {
                vehicles = soslSearchVehicles(cleaned, lim);
            } catch (Exception e) {
                System.debug('@@@ SOSL failed in AF_ValidateVehicleForDealer: ' + e.getMessage());
                vehicles = soqlSearchVehicles(cleaned, lim); // fallback
            }

            if (vehicles.isEmpty()) {
                out.message = 'No vehicles found for "' + req.vehicleName + '". Please try a different model name.';
                results.add(out);
                continue;
            }

            Set<Id> vehicleIds = new Set<Id>();
            Map<Id, Vehicle> vehicleById = new Map<Id, Vehicle>();
            for (Vehicle v : vehicles) {
                vehicleIds.add(v.Id);
                vehicleById.put(v.Id, v);
            }

            // -------- 2) Junction query: Dealer_Vehicle__c determines availability --------
            Map<Id, Boolean> availableByVehicleId = new Map<Id, Boolean>();

            for (Dealer_Vehicle__c dv : [
                SELECT Vehicle__c, Is_Test_Drive_Available__c
                FROM Dealer_Vehicle__c
                WHERE Dealer__c = :req.dealerId
                  AND Vehicle__c IN :vehicleIds
            ]) {
                availableByVehicleId.put(dv.Vehicle__c, dv.Is_Test_Drive_Available__c);
            }

            // Build options: keep vehicles that have a junction record
            // (Because dealer-vehicle relationship is defined by junction)
            List<VehicleOptionDTO> optionsAvailable = new List<VehicleOptionDTO>();
            List<VehicleOptionDTO> optionsNotAvailable = new List<VehicleOptionDTO>();

            for (Vehicle v : vehicles) {
                if (!availableByVehicleId.containsKey(v.Id)) {
                    // Not linked to dealer at all -> skip (or include as not available if you want)
                    continue;
                }

                Boolean isAvail = availableByVehicleId.get(v.Id) == true;
                VehicleOptionDTO dto = new VehicleOptionDTO(v.Id, v.Name, isAvail);

                if (isAvail) optionsAvailable.add(dto);
                else optionsNotAvailable.add(dto);
            }

            // Merge: available first, then unavailable
            List<VehicleOptionDTO> merged = new List<VehicleOptionDTO>();
            merged.addAll(optionsAvailable);
            merged.addAll(optionsNotAvailable);

            out.matchCount = merged.size();
            out.vehicleOptionsJson = JSON.serialize(merged);

            // Build agent-friendly option outputs (no StringBuilder)
            List<String> ids = new List<String>();
            List<String> names = new List<String>();
            List<String> avs = new List<String>();
            List<String> lines = new List<String>();

            for (Integer i = 0; i < merged.size(); i++) {
                VehicleOptionDTO opt = merged[i];
                String availLabel = (opt.isAvailable == true) ? 'Available' : 'Not Available';

                // Numbered list line
                lines.add(String.valueOf(i + 1) + ') ' + opt.name + ' (' + availLabel + ')');

                // CSV lists (best for mapping chosen number -> Id)
                ids.add(String.valueOf(opt.id));
                names.add(opt.name);
                avs.add(String.valueOf(opt.isAvailable));
            }

            out.vehicleOptionsText = String.join(lines, '\n');
            out.optionIdsCsv = String.join(ids, ';');
            out.optionNamesCsv = String.join(names, ';');
            out.optionAvailabilityCsv = String.join(avs, ';');

            if (merged.isEmpty()) {
                out.message = 'Vehicles were found, but none are mapped to this dealer.';
                results.add(out);
                continue;
            }

            // -------- 3) Decide output behavior for agent UX --------
            if (merged.size() == 1) {
                // Single clear choice
                out.vehicleId = merged[0].id;
                out.vehicleNameMatched = merged[0].name;
                out.isAvailable = merged[0].isAvailable;

                out.message = out.isAvailable
                    ? 'Vehicle is available for test drive.'
                    : 'Vehicle is mapped to dealer but not available for test drive.';
            } else {
                // Multiple matches -> ask user to confirm selection
                out.needsUserConfirmation = true;
                out.message = 'Multiple vehicles match "' + req.vehicleName + '". Please choose one.';
            }

            results.add(out);
        }

        return results;
    }

    // ---------- Helpers ----------
    private static Output buildEmpty(String msg) {
        Output out = new Output();
        out.isAvailable = false;
        out.needsUserConfirmation = false;
        out.matchCount = 0;
        out.vehicleOptionsJson = '[]';
        out.vehicleOptionsText = '';
        out.optionIdsCsv = '';
        out.optionNamesCsv = '';
        out.optionAvailabilityCsv = '';
        out.message = msg;
        return out;
    }

    private static String normalize(String s) {
        s = s == null ? '' : s.trim();
        s = s.replaceAll('\\s+', ' ');
        return s;
    }

    /**
     * SOSL search on Vehicle Name with google-like behavior.
     * - If user types multiple words, we build "word1* AND word2*" style search.
     */
    private static List<Vehicle> soslSearchVehicles(String userText, Integer lim) {
        // Split words and create AND query for better relevance
        List<String> tokens = new List<String>();
        for (String t : userText.split('\\s+')) {
            if (!String.isBlank(t)) tokens.add(cleanSoslToken(t));
        }

        if (tokens.isEmpty()) return new List<Vehicle>();

        String sosl = '';
        if (tokens.size() == 1) {
            sosl = tokens[0] + '*';
        } else {
            // token1* AND token2* AND ...
            List<String> parts = new List<String>();
            for (String t : tokens) parts.add(t + '*');
            sosl = String.join(parts, ' AND ');
        }

        List<List<SObject>> res = [
            FIND :sosl IN NAME FIELDS
            RETURNING Vehicle(Id, Name LIMIT :lim)
        ];

        return (List<Vehicle>) res[0];
    }

    private static String cleanSoslToken(String s) {
        // Remove characters that can break SOSL parsing
        // Keep alphanumerics and spaces; replace others with space.
        String cleaned = s.replaceAll('[^a-zA-Z0-9]', ' ');
        cleaned = cleaned.replaceAll('\\s+', ' ').trim();
        return cleaned;
    }

    private static List<Vehicle> soqlSearchVehicles(String userText, Integer lim) {
        String likeTerm = '%' + escapeLike(userText) + '%';
        return [
            SELECT Id, Name
            FROM Vehicle
            WHERE Name LIKE :likeTerm
            ORDER BY Name
            LIMIT :lim
        ];
    }
    
    private static String escapeLike(String s) {
        if (s == null) return '';
        // escape LIKE wildcards
        s = s.replace('\\', '\\\\');
        s = s.replace('%', '\\%');
        s = s.replace('_', '\\_');
        return s;
    }
}

/* Class 2----------------
public with sharing class AF_ValidateVehicleForDealer {

    public class Input {
        @InvocableVariable(required=true description='Dealer Account Id')
        public Id dealerId;

        @InvocableVariable(required=true description='Vehicle Name')
        public String vehicleName;
    }

    public class Output {
        @InvocableVariable public Boolean isAvailable;
        @InvocableVariable public Id vehicleId;
        @InvocableVariable public String vehicleNameMatched;
    }

    @InvocableMethod(
        label='Validate Vehicle for Dealer'
        description='Find a vehicle by name and check its availability at a dealer'
    )
    public static List<Output> validate(List<Input> requests) {

        Output out = new Output();
        out.isAvailable = false;

        if (requests == null || requests.isEmpty()) {
            return new List<Output>{ out };
        }

        Input req = requests[0];

        if (req.dealerId == null || String.isBlank(req.vehicleName)) {
            return new List<Output>{ out };
        }

        // --- CASE-INSENSITIVE VEHICLE NAME SEARCH (SOSL) ---
        List<List<SObject>> searchList = Search.query(
            'FIND \'*' + String.escapeSingleQuotes(req.vehicleName.trim()) + '*\' ' +
            'IN ALL FIELDS RETURNING Vehicle ' +
            '(Id, Name WHERE Dealer__c = \'' + req.dealerId + '\' LIMIT 5)'
        );

        List<Vehicle> vehicles = (List<Vehicle>)searchList[0];

        if (vehicles.isEmpty()) {
            return new List<Output>{ out };
        }

        Vehicle v = vehicles[0];
        out.vehicleId = v.Id;
        out.vehicleNameMatched = v.Name;

        // --- VALIDATE VEHICLE AVAILABILITY ---
        Integer countAvailable = [
            SELECT COUNT()
            FROM Dealer_Vehicle__c
            WHERE Dealer__c = :req.dealerId
            AND Vehicle__c = :v.Id
            AND Is_Test_Drive_Available__c = true
        ];

        out.isAvailable = (countAvailable > 0);

        return new List<Output>{ out };
    }
}*/

/* Class 1----------------
public with sharing class AF_ValidateVehicleForDealer {

    public class Input {
        @InvocableVariable(required=true description='Dealer Account Id')
        public Id dealerId;

        @InvocableVariable(required=true description='Vehicle Name')
        public String vehicleName;
    }

    public class Output {
        @InvocableVariable public Boolean isAvailable;
        @InvocableVariable public Id vehicleId;
        @InvocableVariable public String vehicleNameMatched;
    }

    @InvocableMethod(
        label='Validate Vehicle for Dealer'
        description='Find a vehicle by name and check its availability at a dealer'
    )
    public static List<Output> validate(List<Input> requests) {

        Output out = new Output();
        out.isAvailable = false;

        if (requests == null || requests.isEmpty()) {
            return new List<Output>{ out };
        }

        Input req = requests[0];

        if (req.dealerId == null || String.isBlank(req.vehicleName)) {
            return new List<Output>{ out };
        }

        // Normalize for fuzzy matching (case-insensitive)
        String vn = '%' + req.vehicleName.trim().toLowerCase() + '%';

        // Step 1: Find matching vehicle(s)
        List<Vehicle> vehicles = [
            SELECT Id, Name
            FROM Vehicle
            WHERE LOWER(Name) LIKE :vn
            LIMIT 5
        ];

        if (vehicles.isEmpty()) {
            return new List<Output>{ out };
        }

        // If multiple vehicles match, pick the first or let your topic handle choices
        Vehicle selectedVehicle = vehicles[0];
        out.vehicleId = selectedVehicle.Id;

        // Step 2: Check if selected vehicle is available for this dealer
        Integer countAvailable = [
            SELECT COUNT()
            FROM Dealer_Vehicle__c
            WHERE Dealer__c = :req.dealerId
            AND Vehicle__c = :selectedVehicle.Id
            AND Is_Test_Drive_Available__c = true
        ];

        out.isAvailable = (countAvailable > 0);
        return new List<Output>{ out };
    }
}
*/