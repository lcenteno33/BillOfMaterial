@RestResource(urlmapping='/configurationBOM/v2/*')
global with sharing class ConfigurationBOMController_v2 {

  public static final String BOM_TYPE_ALL_SALES_LINES = 'BOM_TYPE_ALL_SALES_LINES';
  public static final String BOM_TYPE_ORDER_LINES_ONLY = 'BOM_TYPE_ORDER_LINES_ONLY';

  @HttpGet
  global static List<NestedObject> handleGet() {
    RestRequest req = RestContext.request;
   // System.debug('REQUEST');
   // System.debug(req);
    String[] path = req.requestURI.substring(req.requestURI.indexOf('/') + 1).split('/');
    String obj = path[path.indexOf('v2') + 1];
    String id = path[path.indexOf('v2') + 2];
    List<String> fields = new List<String>();
    Boolean salesOnly = false;
    if(req.params.containsKey('fields')) {
      String[] rawFields = req.params.get('fields').split(',');
      for (String rawField : rawFields) {
        fields.add(rawField.trim());
      }
     // System.debug('INSPECT FIELDS');
     // System.debug(fields);
    }
    if(req.params.containsKey('salesOnly')) {
      salesOnly = req.params.get('salesOnly').trim().toLowerCase() == 'true';
    }
    switch on obj {
      when 'order', 'Order' {
        Order o = new Order(Id=id);
        return getBOMsForOrder(o, fields, salesOnly);
      }
      when 'quote', 'Quote', 'SBQQ__Quote__c' {
        SBQQ__Quote__c q = new SBQQ__Quote__c(Id=id);
        return getBOMsForQuote(q, fields, salesOnly);
      }
      when 'opportunity', 'Opportunity' {
        Opportunity op = new Opportunity(Id=id);
       // System.debug('INSIDE OPPTY CASE');
       // System.debug(fields);
        return getBOMsForOpportunity(op, fields, salesOnly);
      }
      when 'salesAgreement', 'SalesAgreement' {
        SalesAgreement sa = new SalesAgreement(Id=id);
       // System.debug('INSIDE OPPTY CASE');
       // System.debug(fields);
        return getBOMsForSalesAgreement(sa, fields, salesOnly);
      }
      when 'orderLine', 'OrderItem', 'OrderLine', 'OrderProduct' {
        OrderItem oi = [SELECT OrderId FROM OrderItem WHERE Id = :id];
        return new List<NestedObject>{getBOMForOrderItem(oi, fields, salesOnly)};
      }
      when 'quoteLine', 'QuoteLine', 'SBQQ__QuoteLine__c' {
        SBQQ__QuoteLine__c ql = [SELECT SBQQ__Quote__c FROM SBQQ__QuoteLine__c WHERE Id = :id];
        return new List<NestedObject>{getBOMForQuoteLine(ql, fields, salesOnly)};
      }
      when 'opportunityLineItem', 'OpportunityLineItem' {
        OpportunityLineItem oli = [SELECT OpportunityId FROM OpportunityLineItem WHERE Id = :id];
        return new List<NestedObject>{getBOMForOpportunityLineItem(oli, fields, salesOnly)};
      }
      when 'salesAgreementProduct', 'SalesAgreementProduct' {
        SalesAgreementProduct sap = [SELECT SalesAgreementId FROM SalesAgreementProduct WHERE Id = :id];
        return new List<NestedObject>{getBOMForSalesAgreementProduct(sap, fields, salesOnly)};
      }
      
      when else {
        return new List<NestedObject>();
      }
    }
  }

  @HttpPost
  global static List<NestedObject> consumePost() {
    IncomingPayload req = (IncomingPayload) JSON.deserialize(RestContext.request.requestBody.toString(), IncomingPayload.class);
    List<NestedObject> fullBoms;
    Boolean salesOnly = false;
    if(req.salesOnly != null) {
      salesOnly = req.salesOnly;
    }
   // System.debug('check consume post');
   // System.debug(req);
    if(req.order != null) {
      return getBOMsForOrder(req.order, req.fields, salesOnly);
    } else if(req.quote != null) {
      return getBOMsForQuote(req.quote, req.fields, salesOnly);
    } else if(req.opportunity != null) {
      return getBOMsForOpportunity(req.opportunity, req.fields, salesOnly);
    } else if(req.salesAgreement != null) {
      return getBOMsForSalesAgreement(req.salesAgreement, req.fields, salesOnly);
    }
     else if(req.quoteLine != null) {
      return new List<NestedObject>{getBOMForQuoteLine(req.quoteLine, req.fields, salesOnly)};
    } else if(req.orderItem != null) {
      return new List<NestedObject>{getBOMForOrderItem(req.orderItem, req.fields, salesOnly)};
    } else if(req.opportunityLineItem != null) {
      return new List<NestedObject>{getBOMForOpportunityLineItem(req.opportunityLineItem, req.fields, salesOnly)};
    } else if(req.salesAgreementProduct != null) {
      return new List<NestedObject>{getBOMForSalesAgreementProduct(req.salesAgreementProduct, req.fields, salesOnly)};
    }

    return new List<NestedObject>();
  }

  private class IncomingPayload {
    Order order;
    SBQQ__Quote__c quote;
    SBQQ__QuoteLine__c quoteLine;
    OrderItem orderItem;
    Opportunity opportunity;
    OpportunityLineItem opportunityLineItem;
    SalesAgreement salesAgreement;
    SalesAgreementProduct salesAgreementProduct;
    List<String> fields;
    Boolean salesOnly;
  }

  @AuraEnabled(cacheable=true)
  public static List<NestedObject> getBOMsForOrder(
    Order order,
    List<String> fields,
    Boolean salesOnly
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      // 'SBQQ__QuoteLine__r.LGK__Logik_Id__c',
      // 'SBQQ__QuoteLine__r.ConfigurationLineItem__c',
      'SBQQ__QuoteLine__r.LGK__ConfigurationId__c',
      'SBQQ__RequiredBy__c',
      'Product2Id',
      'Product2.Name'
    };
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      order.Id, // parentId
      OrderItem.class, // childType
      'OrderId',// childToParentIdField
      'SBQQ__RequiredBy__c', // bundleIdField
      // 'SBQQ__QuoteLine__r.ConfigurationLineItem__c', // configIdField
      'SBQQ__QuoteLine__r.LGK__ConfigurationId__c', // configIdField
      // 'SBQQ__QuoteLine__r.LGK__Logik_Id__c', // configIdField
      'Product2Id', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    if(salesOnly) {
      return removeCfgOnlyNodes(fullBoms);
    }
    return fullBoms;
  }

  public static List<NestedObject> getBOMsForOrder(
    Order order,
    List<String> fields,
    String bomType
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      // 'SBQQ__QuoteLine__r.LGK__Logik_Id__c',
      'SBQQ__QuoteLine__r.LGK__ConfigurationId__c',
      'SBQQ__RequiredBy__c',
      'Product2Id',
      'Product2.Name'
    };
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      order.Id, // parentId
      OrderItem.class, // childType
      'OrderId',// childToParentIdField
      'SBQQ__RequiredBy__c', // bundleIdField
      // 'SBQQ__QuoteLine__r.LGK__Logik_Id__c', // configIdField
      'SBQQ__QuoteLine__r.LGK__ConfigurationId__c', // configIdField
      'Product2Id', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    if(bomType == BOM_TYPE_ORDER_LINES_ONLY) {
      return removeCfgOnlyNodes(fullBoms);
    } else if(bomType == BOM_TYPE_ALL_SALES_LINES) {
      return removeMfgNodes(fullBoms);
    }
    return fullBoms;
  }

  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForAsset(
    Asset asset,
    Date asOfDate,
    List<String> fields,
    Boolean salesOnly
  ) {
    /**
     * 1. Find root asset
     * 2. Retrieve LGK id
     * 3. Get BOM for LGK id
     * 4. 
     */

    /*
    String configId = AssetManagement.getAssetConfigId(asset.RootAssetId, asOfDate);
    if (configId == null) {
      // TODO: throw error
    }
    */
    String configId = null;
    AssetActionSource cfgAas = [SELECT ExternalReference FROM AssetActionSource WHERE ExternalReferenceDataSource = 'Logik Configuration' AND AssetAction.AssetId = :asset.RootAssetId AND AssetAction.ActionDate <= :asOfDate ORDER BY AssetAction.ActionDate DESC LIMIT 1];
    if(cfgAas != null) {
      configId = cfgAas.ExternalReference;
    }
    
    Set<String> queryFields = new Set<String>{
      'Id',
      'Product2Id',
      'RootAssetId',
      'ParentId'
    };
    NestedObject bom = getBOMForObject(
      asset.RootAssetId, // parentId
      Asset.class, // childType
      'RootAssetId', // childToParentIdField
      null, // configIdField
      configId, // configId
      'Product2Id', //productIdField
      new List<String>(queryFields) // queryFields
    );
    return removeMfgNodes(new List<NestedObject>(new NestedObject[]{bom})).get(0);
  }

  @AuraEnabled(cacheable=true)
  public static List<NestedObject> getBOMsForQuote(
    SBQQ__Quote__c quote,
    List<String> fields,
    Boolean salesOnly
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      // 'LGK__Logik_Id__c',
      'LGK__ConfigurationId__c',
      'SBQQ__RequiredBy__c',
      'SBQQ__Product__c',
      //'SBQQ__Product__r.Name',
      'SBQQ__RequiredBy__c'
    };
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      quote.Id, // parentId
      SBQQ__QuoteLine__c.class, // childType
      'SBQQ__Quote__c',// childToParentIdField
      'SBQQ__RequiredBy__c', // bundleIdField
      //'Logik_ID_Twin__c',
      'LGK__ConfigurationId__c',
      //'LGK__Logik_Id__c', // configIdField
      'SBQQ__Product__c', // prodIdField
      new List<String>(queryFields) // queryFields
    );
   System.debug('CHECKING SALES ONLY');
   System.debug(salesOnly);
   System.debug(fullBoms);
    if(salesOnly) {
      return removeCfgOnlyNodes(fullBoms);
    }
    return fullBoms;
  }


  private static List<NestedObject> getBOMsForObject(
    ID parentId,
    Type childType,
    String childToParentIdField,
    String bundleIdField,
    String configIdField,
    String prodIdField,
    List<String> queryFields
  ) {
   
    String query = String.format('SELECT {0} FROM {1} WHERE {2}', new List<String>{String.join(queryFields, ','), childType.getName(), childToParentIdField + ' = \'' + parentId + '\''});
   System.debug('GETBOM INSPECTION');
   System.debug(query);
   System.debug(childType.getName());
    List<NestedObject> boms = new List<NestedObject>();
    List<SObject> lines = Database.query(query);
    List<String> cfgIds = new List<String>();
    Map<ID, SObject> rootLines = new Map<ID, SObject>();
    Map<String, SObject> cfgProdToLine = new Map<String, SObject>();
   System.debug('CHECKING PRODUCT LINES');
   System.debug(lines);
    for (SObject l : lines) {
      ID bundleId = (ID) l.get(bundleIdField);
      ID prodId = (ID) l.get(prodIdField);
      String configId = (String) PWUtils.getField(l, configIdField);

      System.debug('EACH LINE');
      System.debug(l);
      System.debug(bundleId);
      System.debug(prodId);
      System.debug(configId);

      if(configId != null) {
        cfgProdToLine.put(configId + '|' + prodId, l);
        if( !cfgIds.contains(configId)) {
          cfgIds.add(configId);
        }
      } else if(bundleId != null) {
        //check if parent item has a config id and use that instead
        SObject parent = rootLines.get(bundleId);
        String parentConfigId = (String) PWUtils.getField(parent, configIdField);
        if(parentConfigId != null) {
          cfgProdToLine.put(parentConfigId + '|' + prodId, l);
        }
      }
      if(bundleId == null) {
        rootLines.put(l.Id, l);
        if(!cfgProdToLine.containsKey(configId + '|ROOT')) {
          cfgProdToLine.put(configId + '|ROOT', l);
        } else {
          cfgProdToLine.put(configId + '|ROOT', null); // this way it doesn't get reset on a 3rd item.
        }
      }
    }
    System.debug('cfgIds:');
    System.debug(cfgIds);
    for (String configId : cfgIds) {
      NestedObject bom = getBOMForId(configId);
      //System.debug(bom);
      
      System.debug('CFG BOM');
      System.debug(bom.obj);
      for (NestedObject cfg : bom.all()) {
        //// System.debug('EACH CONFIG BOM');
        //// System.debug(cfg);
        
        
        if(cfg.obj == null || cfg.obj.getSObjectType().getDescribe().getName() == childType.getName()){
          continue;
        }
        // String mapKey = configId + '|' + ((LGK__ConfigurationLineItem__c) cfg.obj).LGK__ProductId__c;
        String mapKey = configId + '|' + ((LGK__ConfigurationLineItem__c) cfg.obj).LGK__ProductId__c;
        //System.debug(mapKey);
        SObject l = cfgProdToLine.get(mapKey);
        //System.debug(l);
        if(l != null) {
          cfg.replaceObject(l);
          cfgProdToLine.remove(mapKey);
          //// System.debug('REPLACED');
          //// System.debug(l);
        }
      }
      SObject root = cfgProdToLine.get(configId + '|ROOT');
     // System.debug('ROOT');
     // System.debug(root);
      if(root != null && bom.obj == null) {
        bom.replaceObject(root);
      } else if (root != null) {
        if(cfgProdToLine.containsKey(configId + '|' + PWUtils.getField(root, prodIdField))) {
          // root item was never added to BOM. Add it as a new level in the BOM.
          NestedObject rootBom = new NestedObject(root);
          rootBom.addChild(bom);
          bom = rootBom;
        }
      }
      boms.add(bom);
    }
   // System.debug('FINAL BOM INSPECTION');
   // System.debug(boms);
    return boms;
  }

  private static NestedObject getBOMForObject(
    ID parentId,
    Type childType,
    String childToParentIdField,
    String configIdField,
    String configId,
    String prodIdField,
    List<String> queryFields
  ) {
    String query = String.format('SELECT {0} FROM {1} WHERE {2}', new List<String>{String.join(queryFields, ','), childType.getName(), childToParentIdField + ' = \'' + parentId + '\''});
    List<SObject> lines = Database.query(query);
    Map<ID, SObject> prodToLine = new Map<ID, SObject>();
    for (SObject l : lines) {
      ID prodId = (ID) l.get(prodIdField);
      prodToLine.put(prodId, l);
      if(configId == null && configIdField != null) {
        configId = (String) PWUtils.getField(l, configIdField);
      }
    }
    NestedObject bom = getBOMForId(configId);
    for(NestedObject cfg : bom.all()) {
      if(cfg.obj == null || cfg.obj.getSObjectType().getDescribe().getName() == childType.getName()){
        continue;
      }
      String mapKey = ((LGK__ConfigurationLineItem__c) cfg.obj).LGK__ProductId__c;
      SObject l = prodToLine.get(mapKey);
      if(l != null) {
        cfg.replaceObject(l);
        prodToLine.remove(mapKey);
      }
    }
    return bom;
  }

  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForQuoteLine (
    SBQQ__QuoteLine__c quoteLine,
    List<String> fields,
    Boolean salesOnly
  ){
    List<NestedObject> quoteBoms = getBOMsForQuote(new SBQQ__Quote__c(Id=quoteLine.SBQQ__Quote__c), fields, salesOnly);
  
    for (NestedObject bom : quoteBoms) {
      NestedObject node = bom.findById(quoteLine.Id);
      if(node != null) {
        return node;
      }
    }
    return null;
  }

  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForOrderItem (
    OrderItem orderItem,
    List<String> fields,
    Boolean salesOnly
  ) {
    List<NestedObject> orderBoms = getBOMsForOrder(new Order(Id=orderItem.OrderId), fields, salesOnly);
    for (NestedObject bom : orderBoms) {
      NestedObject node = bom.findById(orderItem.Id);
      if(node != null) {
        return node;
      }
    }
    return null;
  }

  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForOpportunityLineItem (
    OpportunityLineItem opportunityLineItem,
    List<String> fields,
    Boolean salesOnly
  ) {
    List<NestedObject> opportunityBoms = getBOMsForOpportunity(new Opportunity(Id=opportunityLineItem.OpportunityId), fields, salesOnly);
    for (NestedObject bom : opportunityBoms) {
      NestedObject node = bom.findById(opportunityLineItem.Id);
      if(node != null) {
        return node;
      }
    }
    return null;
  }

  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForSalesAgreementProduct (
    SalesAgreementProduct salesAgreementProduct,
    List<String> fields,
    Boolean salesOnly
  ){
    List<NestedObject> salesAgreementBoms = getBOMsForSalesAgreement(new SalesAgreement(Id=salesAgreementProduct.SalesAgreementId), fields, salesOnly);
    for (NestedObject bom : salesAgreementBoms) {
      NestedObject node = bom.findById(salesAgreementProduct.Id);
      if(node != null) {
        return node;
      }
    }
    return null;
  }

  public static NestedObject getBOMForId (String configId) {
   System.debug('INSIDE GETBOM FOR ID');
   System.debug(configId);
   // return new NestedObject(
     //   PWUtils.selectStar('LGK__ConfigurationLineItem__c', 'LGK__Configuration_Id__c = \'' + configId + '\'', new List<String>{'Product__r.Name', 'Parent__r.Product__r.Name', 'Parent__r.Product__c'} ),
     //   'LGK__Unique_Id__c',
     //   'LGK__Parent_Product_Id__c'
     // );
     
     System.debug('LGK__ConfigurationLineItem__c' + 'LGK__ConfigurationId__c = \'' + configId + '\'');
    return new NestedObject(
      PWUtils.selectStar('LGK__ConfigurationLineItem__c', 'LGK__ConfigurationId__c = \'' + configId + '\'', new List<String>{} ),
      'LGK__UniqueId__c',
      'LGK__ParentProductId__c'
    );
  }

  public static List<NestedObject> removeCfgOnlyNodes (List<NestedObject> nos) {
   // System.debug('INSIDE REMOVE CFG');
   // System.debug(nos);
    FilterOnlyMappedLines filter = new FilterOnlyMappedLines();
    List<NestedObject> filtered = new List<NestedObject>();
    for (NestedObject no : nos) {
     // System.debug('inspectin nested objects');
     // System.debug(no);
     // System.debug(filter);
      filtered.addAll(no.filter(filter));
    }
   // System.debug(filtered);
    return filtered;
  }

  public static List<NestedObject> removeMfgNodes (List<NestedObject> nos) {
    FilterOnlySalesLines filter = new FilterOnlySalesLines();
    List<NestedObject> filtered = new List<NestedObject>();
    for (NestedObject no : nos) {
      filtered.addAll(no.filter(filter));
    }
    return filtered;
  }

  public class FilterOnlySalesLines implements NestedObject.FilterFunction {
    public FilterOnlySalesLines(){}
    public Boolean test(SObject obj, Map<String, Boolean> bFlags, Map<String,String> sFlags) {

      if(obj instanceof LGK__ConfigurationLineItem__c) {
        return ((LGK__ConfigurationLineItem__c) obj).LGK__Type__c == 'SALES';
      }
      return true;
      /*
      if(obj instanceof OrderItem) {
        try {
          return ((OrderItem) obj).SBQQ__QuoteLine__c != null;
        } catch (Exception e) {
          return true; // We cannot determine if this is a MFG or SALES item so don't exclude it.
        }
      }
      // Not an order line, assume quote line.
      return (!(obj instanceof LGK__ConfigurationLineItem__c)) || ((LGK__ConfigurationLineItem__c) obj).LGK__Type__c == 'SALES';
      */
    }
  }

  public class FilterOnlyMappedLines implements NestedObject.FilterFunction {
    public FilterOnlyMappedLines(){}
    public Boolean test(SObject obj, Map<String,Boolean> bFlags, Map<String,String> sFlags) {
      return obj == null || obj instanceof OrderItem || obj instanceof SBQQ__QuoteLine__c || obj instanceof OpportunityLineItem || obj instanceof SalesAgreementProduct;
    }
  }



  @AuraEnabled(cacheable=true)
  public static List<NestedObject> getBOMsForOpportunity(
    Opportunity opportunity,
    List<String> fields,
    Boolean salesOnly
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      'Logik_ID_Twin__c',
      'SBQQ__ParentID__c',
      'Product2Id',
      'Product2.Name',
      'Quantity',
      'ListPrice',
      'Discount',
      'UnitPrice',
      'TotalPrice'     

    };
    queryFields.addAll(fields);
   // System.debug('INSIDE BOM OPPTY');
   // System.debug(queryFields);
    List<NestedObject> fullBoms = getBOMsForObject(
      opportunity.Id, // parentId
      OpportunityLineItem.class, // childType
      'OpportunityId',// childToParentIdField
      'SBQQ__ParentID__c', // bundleIdField
      'Logik_ID_Twin__c', // configIdField
      'Product2Id', // prodIdField
      new List<String>(queryFields) // queryFields
    );
   System.debug('FINAL FINAL BOM INSPECTION');
   System.debug(fullBoms);
   // System.debug(salesOnly);
    if(salesOnly) {
      return removeCfgOnlyNodes(fullBoms);
    }
    return fullBoms;
  }

  public static List<NestedObject> getBOMsForOpportunity(
    Opportunity opportunity,
    List<String> fields,
    String bomType
  ) {
    Set<String> queryFields = new Set<String>{
      'OpportunityId',
      'Logik_ID_Twin__c',
      'SBQQ__ParentID__c',
      'Product2Id',
      'Product2.Name',
      'Quantity',
      'ListPrice',
      'Discount',
      'UnitPrice',
      'TotalPrice'
    };
   // System.debug('INSIDE GET BOMS FOR OPPORTUNITY');
   // System.debug(queryFields);
   // System.debug(fields);
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      opportunity.Id, // parentId
      OpportunityLineItem.class, // childType
      'OpportunityId',// childToParentIdField
      'SBQQ__ParentID__c', // bundleIdField
      'Logik_ID_Twin__c', // configIdField
      'Product2Id', // prodIdField
      new List<String>(queryFields) // queryFields
    );
   // System.debug('BOM TYPE');
   // System.debug(bomType);
    if(bomType == BOM_TYPE_ORDER_LINES_ONLY) {
      return removeCfgOnlyNodes(fullBoms);
    } else if(bomType == BOM_TYPE_ALL_SALES_LINES) {
      return removeMfgNodes(fullBoms);
    }
   // System.debug(fullBoms);
    return fullBoms;
  }



  @AuraEnabled(cacheable=true)
  public static List<NestedObject> getBOMsForSalesAgreement(
    SalesAgreement salesAgreement,
    List<String> fields,
    Boolean salesOnly
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      'Logik_ID_Twin__c',
      'Parent_Quote_Line__c',
      'ProductId',
      'Product.Name',
      'TotalPlannedQuantity',
      'ListPrice',
      'DiscountPercentage',
      'SalesPrice',
      'TotalPlannedAmount'
    };
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      salesAgreement.Id, // parentId
      SalesAgreementProduct.class, // childType
      'SalesAgreementId',// childToParentIdField
      'Parent_Quote_Line__c', // bundleIdField
      'Logik_ID_Twin__c', // configIdField
      'ProductId', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    // if(salesOnly) {
    //   return removeCfgOnlyNodes(fullBoms);
    // }
    return fullBoms;
  }

  public static List<NestedObject> getBOMsForSalesAgreement(
    SalesAgreement salesAgreement,
    List<String> fields,
    String bomType
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      'Logik_ID_Twin__c',
      'Parent_Quote_Line__c',
      'ProductId',
      'Product.Name',
      'TotalPlannedQuantity',
      'ListPrice',
      'DiscountPercentage',
      'SalesPrice',
      'TotalPlannedAmount'
    };
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      salesAgreement.Id, // parentId
      SalesAgreementProduct.class, // childType
      'SalesAgreementId',// childToParentIdField
      'Parent_Quote_Line__c', // bundleIdField
      'Logik_ID_Twin__c', // configIdField
      'ProductId', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    // if(bomType == BOM_TYPE_ORDER_LINES_ONLY) {
    //   return removeCfgOnlyNodes(fullBoms);
    // } else if(bomType == BOM_TYPE_ALL_SALES_LINES) {
    //   return removeMfgNodes(fullBoms);
    // }
    return fullBoms;
  }




}