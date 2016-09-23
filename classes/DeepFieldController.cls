public class DeepFieldController {
	public string currentobject { get; set; }
	public string currentfield { get; set; }
	
    //what to query by - standard object name or SObject ID for custom objects
    private string queryBy;
    
	public selectoption[] getobjects() {
		selectoption[] objects = new selectoption[0];
		map<string,schema.sobjecttype> describe = schema.getglobaldescribe();
		for(string objectname:describe.keyset()) {
			objects.add(new selectoption(objectname,describe.get(objectname).getdescribe().getName()));
		}
        
        //Sort object names alphabetically
        objects.sort();
        
        if(String.isEmpty(currentobject)) {
	        currentobject = objects[0].getValue();
        }
        
		return objects;
	}
	
	public selectoption[] getfields() {
		selectoption[] fields = new selectoption[0];
        
		map<string,schema.sobjecttype> describe = schema.getglobaldescribe();
		
        if(describe.containskey(currentobject)) {
			map<string,schema.sobjectfield> fieldmap = describe.get(currentobject).getdescribe().fields.getmap();
			for(string fieldname:fieldmap.keyset()) {
				fields.add(new selectoption(fieldname,fieldmap.get(fieldname).getdescribe().getname()));
			}
		}
        
		return fields;
	}
    
    //Submit an HTTP GET request
    public String getHTTP(String svcURL) {
        //HTTP objects
        HttpRequest req = new HttpRequest();
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionID());
        req.setHeader('Content-Type', 'application/json');
        
        String domainUrl = URL.getSalesforceBaseUrl().toExternalForm();
        
        req.setEndpoint(domainUrl + svcURL);
        req.setMethod('GET'); 
                
        Http h = new Http();
        HttpResponse res = h.send(req);
	
        return res.getBody();
    }
    
    private void setWhereUsed() {        
        if(String.isNotEmpty(currentObject) && currentObject.contains('__c')) {            
            //Get name, ex: Hotel__c to Hotel
            map<string,schema.sobjecttype> describe = schema.getglobaldescribe();
            
            if(describe.containskey(currentobject)) {
                string currentObjectLabel = describe.get(currentobject).getdescribe().getLabel();
             
                //Convert Name to SObject ID
                String response = getHTTP('/services/data/v37.0/tooling/query/?q=Select+id+from+CustomObject+WHERE+DeveloperName=\'' + currentObjectLabel + '\'');
                        		
                Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(response);
                List<Object> records = (List<Object>) resultMap.get('records');
                
                Map<String, Object> row = (Map<String, Object>) records[0];
                
                queryBy = (string) row.get('Id'); 
            }
        }
        else {
			queryBy = currentobject;            
        }
    }
    
    //Get formula fields where field is used
    public String getFormulaFieldUsage() {
        setWhereUsed();
        
        String retVal = '';
        
        //Pull custom field rows
        String response = getHTTP('/services/data/v37.0/tooling/query/?q=SELECT+DeveloperName+FROM+CustomField+WHERE+TableEnumOrId=\'' + queryBy + '\'');
        
        //Pull URL for each custom field
		Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(response);
        List<Object> records = (List<Object>) resultMap.get('records');
                
        for (Integer i = 0; i < records.size(); i++) {
            Map<String, Object> row = (Map<String, Object>) records[i];
            
            string fieldName = (string) row.get('DeveloperName');
            
        	Map<String, Object> attributeMap = (Map<String, Object>) row.get('attributes');    
            
            //Pull metadata for each custom field
            String customFieldResponse = getHTTP((string) attributeMap.get('url'));

            //Check if metadata contains field name under formula
            //"formula" : null, or "formula" : "LOWER(AgentName__c)",
            //NOT helps distinguish AgentName__c and Name__c
            pattern formulaPattern = pattern.compile('(?i).*"formula":"(.*[^a-zA-Z0-9_]' + currentfield + '.*)","formulaTreatBlanksAs".*');
            matcher formulaMatcher = formulaPattern.matcher(customFieldResponse);
            
            if(formulaMatcher.matches()) {
                retVal += fieldName + ' ' + formulaMatcher.group(1);
            }
        }
        
        return retVal;        
    }
    
    //Get apex classes where field is used
    public List<String> getClassUsage() { 
        List<String> retVal = new List<String>();
        
        String response = getHTTP('/services/data/v37.0/tooling/search/?q=FIND+{' + currentobject + '+AND+' + currentfield + '}+IN+ALL+FIELDS+RETURNING+ApexClass+(Name)');
        
        retVal.add(response);
        
        return retVal;
    }
    
    //Get layouts where field is used
    public List<String> getLayoutUsage() { 
        setWhereUsed();

        List<String> retVal = new List<String>();
        
        //Pull layout rows
        String response = getHTTP('/services/data/v37.0/tooling/query/?q=SELECT+EntityDefinitionID,LayoutType,ManageableState,Name,NamespacePrefix,TableEnumOrID+FROM+Layout+WHERE+TableEnumOrId=\'' + queryBy + '\'');
        
        //Pull URL for each layout
		Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(response);
        List<Object> records = (List<Object>) resultMap.get('records');
                
        for (Integer i = 0; i < records.size(); i++) {
            Map<String, Object> row = (Map<String, Object>) records[i];
            
            string layoutName = (string) row.get('Name');
            
        	Map<String, Object> attributeMap = (Map<String, Object>) row.get('attributes');    
            
            //Pull metadata for each layout
            String layoutResponse = getHTTP((string) attributeMap.get('url'));
            
            //Check if metadata contains field name
            if(layoutResponse.containsIgnoreCase('"field":"' + currentfield + '"')) {
                retVal.add(layoutName);
            }
        }
        
        return retVal;
    }
}