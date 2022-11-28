global class NestedObject {
    @AuraEnabled
    public List<NestedObject> children;
    @AuraEnabled
    public Id parentId;
    private Id rootId;
    @AuraEnabled
    public SObject obj;
    private Map<String, Boolean> bFlags = new Map<String, Boolean>();
    private Map<String, String> sFlags = new Map<String, String>();

    /**
     * @param obj the base object to create the NestedObject from
     * @description Basic constructor
     */
    public NestedObject (SObject obj) {
        this.obj = obj;
        this.rootId = obj.Id;
    }

    public NestedObject (AssignResult ar) {
        this.obj = ar.obj;
        this.rootId = ar.obj.id;
        this.bFlags = ar.bFlags;
        this.sFlags = ar.sFlags;
    }

    /** 
     * @param objs List of SObjects to create the nested object from
     * @param key Field (String) to be used as identifier of an SObject instance in objs for purposes of establishing parent-child relationship.
     * @param parentKey Field (String) to be used as identifer of the parent of an SObject instance in objs. The SObject instance in objs with it's 'key' value equal to the value of 'parentKey' is the parent of any particular instance.
     */
    public NestedObject (List<SObject> objs, String key, String parentKey) {
        List<String> addedKeys = new List<String>();
        List<SObject> working = objs;
        List<SObject> staged = new List<SObject>();
        Boolean rootFound = false;
        Boolean multiRoot = false;
        while (working.size() > 0) {
            Integer count = 0;
            for (SObject obj : working) {
                count++;
                String parentId = (String) obj.get(parentKey);
                if(parentId == null || parentId == 'null' || parentId == '') {
                    if(rootFound && !multiRoot) {
                        //multiple roots
                        NestedObject selfClone = this.clone();
                        this.obj = this.obj.Id.getSObjectType().newSObject();
                        this.children = new List<NestedObject>{selfClone};
                        this.rootId = this.obj.Id;
                        this.resetIds(true);
                        this.addChild(obj);
                        multiRoot = true;
                    } else if (rootFound && multiRoot) {
                        this.addChild(obj);
                    } else {
                        this.obj = obj;
                        this.rootId = obj.Id;
                    }
                    rootFound = true;
                    addedKeys.add((String) obj.get(key));
                } else if (addedKeys.contains(parentId)) {
                    NestedObject parent = this.findByKey(key, parentId);
                    if(parent != null) {
                        parent.addChild(obj);
                        addedKeys.add((String) obj.get(key));
                    }
                } else {
                    staged.add(obj); // come back once the parent has been added
                }
            }
            working = staged;
            staged = new List<SObject>();
        }
    }

    private NestedObject (SObject obj, NestedObject parent) {
        this.obj = obj;
        this.parentId = parent.obj.Id;
        this.rootId = parent.rootId;
    }

    public void addChild(SObject child) {
        if(this.children == null) {
            this.children = new List<NestedObject>();
        }
        this.children.add(new NestedObject(child, this));
    }

    public void addChild(NestedObject child) {
        if(this.children == null) {
            this.children = new List<NestedObject>();
        }
        child.parentId = this.obj.Id;
        child.rootId = this.rootId;
        this.children.add(child);
    }

    public NestedObject findById (Id id) {
        if(this.obj.Id == id) {
            return this;
        } else if (this.children != null) {
            for (NestedObject child : this.children) {
                NestedObject found = child.findById(id);
                if(found != null) {
                    return found;
                }
            }
        }
        return null;
    }
    
    public NestedObject findByKey (String keyField, String keyValue) {
        if(this.obj.get(keyField) == keyValue) {
            return this;
        } else if (this.children != null) {
            for (NestedObject child : this.children) {
                NestedObject found = child.findByKey(keyField, keyValue);
                if(found != null) {
                    return found;
                }
            }
        }
        return null;
    }
    
    public List<NestedObject> all() {
        List<NestedObject> all = new List<NestedObject>();
        all.add(this);
        if(this.children != null) {
            for (NestedObject child : this.children) {
                all.addAll(child.all());
            }
        }
        return all;
    }

    public List<NestedObject> some(FilterFunction func) {
        List<NestedObject> filteredList = new List<NestedObject>();
        for (NestedObject node : this.all()) {
            if(func.test(node.obj, node.bFlags, node.sFlags)) {
                filteredList.add(node);
            }
        }
        return filteredList;
    }

    public NestedObject find(FilterFunction func) {
        for (NestedObject node : this.all()) {
            if(func.test(node.obj, node.bFlags, node.sFlags)) {
                return node;
            }
        }
        return null;
    }

    private void resetIds(Boolean rootChanged) {
        if(this.children != null) {
            for(NestedObject child : this.children) {
                child.parentId = this.obj.Id;
            }
            if(rootChanged) {
                for (NestedObject obj : this.all()) {
                    obj.rootId = this.rootId;
                }
            }
        }
    }

    public void replaceObject(SObject obj) {
        Boolean rootChanged = false;
        if((this.rootId == null && obj.Id != null) || this.rootId == this.obj.Id) {
            // this is the root item
            this.rootId = obj.Id;
            rootChanged = true;
        }
        this.obj = obj;
        this.resetIds(rootChanged);
    }

    public List<NestedObject> filter(FilterFunction func) {
        // 1. get filtered list of children, calling this method recursively on each
        List<NestedObject> children;
        if(this.children != null) {
            children = new List<NestedObject>();
            for (NestedObject no : this.children) {
                List<NestedObject> filteredChildren = no.filter(func);
                if(filteredChildren != null) {
                    children.addAll(filteredChildren);
                }
            }
            if(children.size() == 0) {
                children = null;
            }
        }
        // 2. If this object is valid, return only this object (after resetting any ids)
        if(func.test(this.obj, this.bFlags, this.sFlags)) {
            NestedObject clone = this.clone();
            clone.children = children;
            clone.resetIds(false);
            clone.parentId = null; // this should get reset when it's ultimate parent calls resetIds(), but if it ends up not having a parent, it will stay null (which is good)
            return new List<NestedObject>{clone};
        } else {
            // 3. Else return only the children, omitting this node
            return children;
        }
    }

    public NestedObject rollUp(RollUpFunction func) {
        List<NestedObject> rolledUpChildObjs = new List<NestedObject>();
        if(this.children != null) {
            for (NestedObject child : this.children) {
                child.rollUp(func);
                rolledUpChildObjs.add(child);
            }
        }
        func.forEach(this, rolledUpChildObjs);
        return this;
    }

    public static NestedObject assign(NestedObject target, NestedObject source, String targetIdField, String sourceIdField, String sourceParentIdField, FilterFunction scopeFunc, AssignFunction assignFunc) {
        // iterate over source nodes and search target for matching node, based on source and target ID fields
        //      if there's a match, call assignFunc to determine resulting sObj and flags to replace match in target
        //      if there's no match, look for a match on the source parent and add source node as new child to that parent.
        //      if a scopeFunc is provided, limit the above to only those nodes that pass the scopeFunc filtering (this is primarily for performance & any gov limits in the assignment function)
        //      
        NestedObject result = target.clone();
        List<NestedObject> filteredSource = new List<NestedObject>{source};
        if(scopeFunc != null) {
            filteredSource = source.filter(scopeFunc);
        }
        for (NestedObject rootNO : filteredSource) {
            for (NestedObject baseNO : rootNO.all()) {
                NestedObject no = baseNO;
                if(scopeFunc != null) {
                    // If source is filtered, retrieve the base node from the source based on the filtered node (the filtering will have changed the parental relationships, etc.)
                    no = source.findById(baseNO.obj.Id);
                }
                NestedObject match = result.findByKey(targetIdField, (String) PWUtils.getField(no.obj, sourceIdField));
                if(match != null) {
                    AssignResult assignResult = assignFunc.assign(match.obj, no.obj, match.bFlags, match.sFlags);
                    match.obj = assignResult.obj;
                    match.bFlags = assignResult.bFlags;
                    match.sFlags = assignResult.sFlags;
                } else {
                    NestedObject parentMatch = result.findByKey(targetIdField, (String) PWUtils.getField(no.obj, sourceParentIdField));
                    if(parentMatch != null) {
                        AssignResult assignResult = assignFunc.assign(null, no.obj, new Map<String, Boolean>(), new Map<String, String>());
                        parentMatch.addChild(new NestedObject(assignResult));
                    }
                }
            }
        }
        return result;
    }

    public void setFlag (String key, Boolean val) {
        this.bFlags.put(key, val);
    }

    public void setFlag (String key, String val) {
        this.sFlags.put(key, val);
    }

    public Boolean getBFlag (String key) {
        return this.bFlags.get(key);
    }

    public String getSFlag (String key) {
        return this.sFlags.get(key);
    }
    
    public interface FilterFunction {
        Boolean test(SObject obj, Map<String, Boolean> bFlags, Map<String, String> sFlags);
    }

    public interface RollUpFunction {
        void forEach(NestedObject no, List<NestedObject> children);
    }

    public class AssignResult {
        public Map<String, Boolean> bFlags;
        public Map<String, String> sFlags;
        public SObject obj;

        public AssignResult(){
            this.bFlags = new Map<String, Boolean>();
            this.sFlags = new Map<String, String>();
        }

        public AssignResult(SObject obj, Map<String, Boolean> bFlags, Map<String, String> sFlags) {
            this.obj = obj;
            this.bFlags = bFlags;
            this.sFlags = sFlags;
        }
    }
    
    public interface AssignFunction {
        AssignResult assign(SObject targetObj, SObject sourceObj, Map<String, Boolean> bFlags, Map<String, String> sFlags);
    }

}