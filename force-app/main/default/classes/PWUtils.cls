global class PWUtils {
    public static Object getField(SObject obj, String fieldPath) {
        String[] fieldPathComponents = fieldPath.split('\\.');
        Object fieldVal = null;
        if(fieldPathComponents.size() == 1) {
          fieldVal = obj.get(fieldPath);
        } else if(fieldPathComponents.size() > 1) {
          SObject relatedObj = obj.getSObject(fieldPathComponents[0]);
          if(relatedObj != null) {
            fieldVal = getField(relatedObj, String.join(slice(fieldPathComponents,1,null), '.'));
          }
        }
        return fieldVal;
    }

    public static List<Object> slice (List<Object> objList, Integer startIdx, Integer endIdx) {
        if(startIdx == null) {
            startIdx = 0;
        }
        if(endIdx == null || endIdx == -1) {
            endIdx = objList.size();
        }
        List<Object> result = new List<Object>();
        for (Integer i = startIdx; i < endIdx; i++) {
            result.add(objList.get(i));
        }
        return result;
    }

    public static List<SObject> selectStar(
        String sobjectName,
        String whereClause,
        String[] expandFields
    ) {
        Set<String> fieldNames = schema.describeSObjects(
            new List<String>{ sobjectName }
        )[0]
        .fields.getMap()
        .keyset();
        List<String> iterableFields = new List<String>(fieldNames);
        iterableFields.addAll(expandFields);

        return Database.query(
        String.format(
            'SELECT {0} FROM {1} WHERE {2}',
            new List<String>{
            String.join(iterableFields, ','),
            sobjectName,
            whereClause
            }
        )
        );
    }
}