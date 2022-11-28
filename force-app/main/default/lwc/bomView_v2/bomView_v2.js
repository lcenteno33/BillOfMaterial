import { LightningElement, wire, track, api } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import { getRelatedListInfo } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';

import getBOMs_order from '@salesforce/apex/ConfigurationBOMController_v2.getBOMsForOrder';
import getBOMs_quote from '@salesforce/apex/ConfigurationBOMController_v2.getBOMsForQuote';
import getBOMs_opportunity from '@salesforce/apex/ConfigurationBOMController_v2.getBOMsForOpportunity';
import getBOMs_salesAgreement from '@salesforce/apex/ConfigurationBOMController_v2.getBOMsForSalesAgreement';

const PROD_REL = {
    'SBQQ__QuoteLine__c': 'SBQQ__Product__r',
    'OrderItem': 'Product2',
    'OpportunityLineItem': 'Product2',
    'SalesAgreementProduct': 'Product'
};

const RELATED_LISTS = {
    'SBQQ__Quote__c': 'SBQQ__LineItems__r',
    'Order': 'OrderItems',
    'Opportunity': 'OpportunityLineItems',
    'SalesAgreement': 'SalesAgreementProducts_WRONG' //put in wrong related list to user override instead
};

const NAME_KEYS = ['Name', 'OrderItemNumber', 'Name', 'Name'];




const actions = [
    { label: 'Edit', name: 'edit_record' }
];
const ACTION_COL = {
    type: 'action',
    label: '',
    typeAttributes: {
        rowActions: actions,
        menuAlignment: 'right'
    }
};
const COLS = [{
    fieldName: '_target',
    label: 'Name',
    type: 'url',
    typeAttributes: {
        label: { fieldName: '_name' }
    }
},
{
    fieldName: '_parent',
    type: 'url',
    label: 'Parent',
    typeAttributes: {
        label: { fieldName: '_parentName' }
    }
},
{
    fieldName: '_quantity',
    type: 'TextArea',
    label: 'Quantity',
    typeAttributes: {
        label: { fieldName: '_quantity' }
    }
},
{
    fieldName: '_listPrice',
    type: 'currency',
    label: 'List Price',
    typeAttributes: {
        label: { fieldName: '_listPrice' }
    }
},
{
    fieldName: '_discount',
    type: 'percentage',
    label: 'Discount',
    typeAttributes: {
        label: { fieldName: '_discount' }
    }
},
{
    fieldName: '_totalPrice',
    type: 'currency',
    label: 'Total Price',
    typeAttributes: {
        label: { fieldName: '_totalPrice' }
    }
},
    ACTION_COL
];



const BOM_FIELDS = [
    'LGK__ConfigurationLineItem__c.Id',
    'LGK__ConfigurationLineItem__c.Name',
    'LGK__ConfigurationLineItem__c.Parent__c',
    'LGK__ConfigurationLineItem__c.LGK__Configuration_Id__c',
    'LGK__ConfigurationLineItem__c.LGK__Notes__c'
];

function nestedFind(obj, testFn) {
    if (Array.isArray(obj)) {
        for (let arrVal of obj) {
            if (typeof arrVal === 'object') {
                let found = nestedFind(arrVal, testFn);
                if (found) {
                    return found;
                }
            }
        }
    } else if (testFn(obj)) {
        return obj;
    }
    for (let [, val] of Object.entries(obj)) {
        if (typeof val === 'object') { // includes arrays and plain objects
            let found = nestedFind(val, testFn);
            if (found) {
                return found;
            }
        }
    }
    return null;
}



export default class BOMGrid extends NavigationMixin(LightningElement) {

   

    @api recordId;
    _objectApiName;
    @track fields = [];
    SBQQ__Quote__c = {};
    // LGK__ConfigurationLineItem__c = {};
    Order = {};
    Opportunity = {};
    SalesAgreement = {};
    @track records = [];
    columns = COLS;
    error;
    show = true;
    objInfo = [];
    @track relatedListId;
    @track salesOnly = true;
    prodRel = null;
    headerTitle = 'BOM Viewer';
    recordCount = 0;
    @track expandedRows = [];
    @track description = '';

    get includeMfgItems() {
        return !this.salesOnly;
    } set includeMfgItems(incl) {
        this.salesOnly = !incl;
    }

    @api get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(apiName) {
        this._objectApiName = apiName;
        this[apiName] = { Id: this.recordId };
        this.relatedListId = RELATED_LISTS[apiName];
    }

    @wire(getRelatedListInfo, { parentObjectApiName: '$objectApiName', relatedListId: '$relatedListId' })
    parseRelatedListInfo({ error, data }) {
        console.log('WIRE INSPECTION');
        console.log(error);
        console.log(data);
        console.log(this);
        if (error) {
            this.error = error;
        } else if (data) {
            console.log('WE GOT DATA');
            this.prodRel = PROD_REL[data.objectApiNames[0]];
            this.headerTitle = `BOM Viewer - ${data.label}`;
            this.columns = [
                ...data.displayColumns.map(col => ({
                    fieldName: NAME_KEYS.includes(col.fieldApiName) ? '_target' : col.fieldApiName.endsWith('.Name') ? col.fieldApiName.replace('.Name', '._target') : col.fieldApiName,
                    label: col.label,
                    wrapText: true,
                    type: NAME_KEYS.includes(col.fieldApiName) || col.fieldApiName.endsWith('.Name') ? 'url' : this.getFieldDataType(col.fieldApiName, data.objectApiNames[0])?.toLowerCase(),
                    typeAttributes: NAME_KEYS.includes(col.fieldApiName) || col.fieldApiName.endsWith('.Name') ? {
                        label: { fieldName: col.fieldApiName }
                    // } : col.fieldApiName.endsWith('.Name') ? {
                    //     label: { fieldName: col.fieldApiName }
                    } : {minimumFractionDigits: '2'}
                })),
                ACTION_COL];
            console.log('INSPECTION');
            console.log(this.columns);
            console.log(data.displayColumns);
            this.fields = data.displayColumns.map(col => col.fieldApiName);
            console.log(this.fields);
        }
    }

    @wire(getObjectInfos, { objectApiNames: ['LGK__ConfigurationLineItem__c', 'SBQQ__QuoteLine__c', 'OrderItem', 'OpportunityLineItem', 'SalesAgreementProduct'] })
    parseObjInfo({ error, data }) {
        if (error) {
            this.error = error;
        } else if (data) {
            this.objInfo = data.results.map(({ result }) => result);
        }
    }

    /** 
     * @description Set data for the base record--either bomNode (for LGK__ConfigurationLineItem__c records) or quoteLine (for SBQQ__QuoteLine__c or OrderItem records) 
     */
    @wire(getRecord, { recordId: '$recordId', fields: [] })
    setRecordData({ error, data }) {
        if (error) {
            this.error = error;
        } else if (data) {
            this[this.objectApiName] = { Id: data.id };
        }
    }
    /**
     * @description set descendant data based on bomNode
     * @param {*} {bomNode}
     */
    // @wire(getDescendants_bn, { bomNode: '$LGK__ConfigurationLineItem__c' })
    wiredData({ error, data }) {
        console.log('DATA INSPECTION on Wired Data');
        console.log(data);
        if (error) {
            this.error = error;
        } else if (data && data.length) {
            this.show = true;
            const rawRecords = JSON.parse(JSON.stringify(data));
            this.recordCount = this.countRecords(rawRecords);
            console.log(rawRecords);
            this.expandedRows = this.getExpandedRows(rawRecords);
            this.parseRecords(rawRecords).then(records => {
              
                this.records = [...records];
               
                
            });
        }
    }
    /**
     * @description set descendant data based on quoteLine
     * @param {*} param0 a
     */
    @wire(getBOMs_quote, { quote: '$SBQQ__Quote__c', fields: '$fields', salesOnly: '$salesOnly' })
    wiredDataFromQuote({ error, data }) {
        if (data) {
            console.log('WIRED DATA from QUOTE: ', data);
            this.wiredData({ error, data });
        }
    }
    /**
     * @description set descendant data based on orderLine
     * @param {*} param0 
     */
    @wire(getBOMs_order, { order: '$Order', fields: '$fields', salesOnly: '$salesOnly' })
    wiredDataFromOrder({ error, data }) {
        this.wiredData({ error, data });
    }
    /**
     * @description set descendant data based on opportunityLine
     * @param {*} param0 
     */
       @wire(getBOMs_opportunity, { opportunity: '$Opportunity', fields: '$fields', salesOnly: '$salesOnly' })
       wiredDataFromOpportunity({ error, data }) {
            console.log('WIRED DATA from Opportunity: ', data);
           this.wiredData({ error, data });
    }
    /**
     * @description set descendant data based on salesAgreementProduct
     * @param {*} param0 
     */
     @wire(getBOMs_salesAgreement, { salesAgreement: '$SalesAgreement', fields: '$fields', salesOnly: '$salesOnly' })
     wiredDataFromSalesAgreement({ error, data }) {
         this.wiredData({ error, data });
     }


    getFieldDataType(fieldApiName, objectApiName) {
        const fieldComps = fieldApiName.split('.');
        console.log('Inspecting Field Data Types');
        console.log(fieldComps);
        console.log(this.objInfo);
        console.log(this.objInfo.find(obj => obj.apiName == objectApiName)?.fields?.[fieldApiName]?.dataType);
        if (fieldComps.length == 1) {
            return this.objInfo.find(obj => obj.apiName == objectApiName)?.fields?.[fieldApiName]?.dataType;
        } else if (fieldComps.length == 2) {
            return fieldComps[1] == 'Name' ? 'text' : Object.values(this.objInfo.find(obj => obj.apiName == objectApiName)?.fields).find(field => field.relationshipName == fieldComps[0])?.dataType;
        }
    }

    // parseData(data, nested = false) {
    //     const target = {};
    //     if (data.id) {
    //         target.Id = data.id;
    //     }
    //     // Object.entries(data.fields).forEach(([key, { value }]) => { target[key] = (value && typeof value === 'object') ? this.parseData(value, true) : value });
    //     if (!nested) {
    //         this[this.objectApiName] = target;
    //     }
    //     return target;
    // }

    addLink(record) {
        
        const proms = [];
        if (record?.parentId) {
            proms.push(this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: record.parentId,
                    actionName: 'view',
                }
            }).then(url => { record._parent = url }));
        }
        proms.push(this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: record.objType == 'LGK__ConfigurationLineItem__c' ? record.Product__c : record.Id,
                actionName: 'view',
            }
        }).then(url => { record._target = url }));
        
        for(let [key, val] of Object.entries(record)) {
            if(['children', '_children', 'obj'].includes(key)) {
                continue;
            }
            if(val && typeof val == 'object') {
                let iObjId = val.Id ? val.Id : record[key + 'Id']; // e.g. record.Product2.Id or record.Product2Id 
                for (let [iKey, iVal] of Object.entries(val)) {
                    if(NAME_KEYS.includes(iKey)) {
                        val._name = iVal;
                        proms.push(this[NavigationMixin.GenerateUrl]({
                            type: 'standard__recordPage',
                            attributes: {
                                recordId: iObjId,
                                actionName: 'view'
                            }
                        }).then(url => { record[key + '._target'] = url }));
                        break;
                    }
                }
            }
        }
        return Promise.all(proms).then(() => record);
    }

    // addLinks(records) {
    //     return Promise.all(records.map(record => {
    //         return Promise.all([
    //             this.addLink(record),
    //             record._children ? this.addLinks(record._children) : Promise.resolve()
    //         ]);
    //     }));
    // }

    getName(obj) {
        switch (this.getObjType(obj)) {
            case 'LGK__ConfigurationLineItem__c':
                    return obj.LGK__UniqueId__c; // + ' ' + obj.LGK__Type__c;
            case 'SBQQ__QuoteLine__c':
                return obj.Name ?? obj.SBQQ__Product__r.Name;
            case 'OpportunityLineItem':
                return obj.Name ?? obj.Product2.Name;
            case 'SalesAgreementProduct':
                return obj.Name ?? obj.Product.Name;
            case 'OrderItem':
                return obj.Name ?? obj.Product2.Name;
            default:
                return null;
        }
    }

    getFieldValue(obj, fieldApiName) {
        return obj[fieldApiName] ?? obj[fieldApiName];
    }

    getObjType(obj) {   
            return this.objInfo.find(info => obj.Id.startsWith(info.keyPrefix))?.apiName;
    }

    flatten(obj) {
        if(this.getObjType(obj) == 'LGK__ConfigurationLineItem__c' && this.prodRel) {
            obj[this.prodRel] = obj['Product__r']; // copy the product record to mimic the target column structure
        }
        Object.entries(obj).forEach(([key, val]) => {
            if (val && typeof val == 'object') {
                for (let innerKey in val) {
                    obj[key + '.' + innerKey] = obj[key][innerKey];
                    if (innerKey == 'Id') {
                        obj[key + '._target'] =
                            this[NavigationMixin.GenerateUrl]({
                                type: 'standard__recordPage',
                                attributes: {
                                    recordId: obj[key][innerKey],
                                    actionName: 'view',
                                }
                            }).then(url => { obj[key + '._target'] = url });
                    }
                }
            }
        });
        return obj;
    }

    countRecords(records) {
        if(!records) {
            return 0;
        }
        let count = 0;
        records.forEach(rec => {
            count+= 1 + this.countRecords(rec.children);
        });
        return count;
    }

    getExpandedRows(records){
        var retArray = [];
        if(!records) {
            return retArray;
        }
        else{
            retArray.push(records[0].obj.Id); //Quote Line Model
            retArray.push(records[0].children[0].obj.Id); //Logik Top Line Model
        }
        
        let count = 0;
        // records[0].children.forEach(rec => {
        //     console.log('each record');
        //     console.log(rec);
            
            
        // });
        return retArray;
    }

    async parseRecords(records, parent) {
        console.log('INSIDE PARSE RECORDS');
        console.log(records);
        console.log(parent);
        return Promise.all(records.map(async tree => {
            // There seems to be a bug with how SF transpiles async functions to generators when the function is self-referencing. Instead of using yield* it only uses yield.
            var childRecs = [];
        
           
                childRecs = tree.children ? await this.parseRecords(tree.children, { ...tree.obj, _name: this.getName(tree.obj) }) : null; 
        
            
            console.log(tree);
            var extendedInfo = this.getFieldValue(tree.obj, 'LGK__Extended_Information__c');
            var extendedInformationKeys = [];
            var extendedInformationValues = [];
            var description = "";
            if(extendedInfo){
                var extendedInfoObject = JSON.parse(extendedInfo);
                console.log(extendedInfoObject);
                console.log(Object.keys(extendedInfoObject));
                extendedInformationKeys = Object.keys(extendedInfoObject);
                extendedInformationValues = Object.values(extendedInfoObject);
                

                console.log('INSPECTING KEYS AND BUILDING DESCIPRITION');
                extendedInformationKeys.forEach(function(key, i){
                    console.log(key);
                    console.log(extendedInformationValues[i]);
                    if(description != ""){description = description + "\n";}
                    description = description + key + ": " + extendedInformationValues[i];
                });
                console.log(description);
                

                

            }
            switch (this.getObjType(tree.obj)) {
                case 'LGK__ConfigurationLineItem__c':
                    return this.addLink({
                        ...tree,
                        ...this.flatten(tree.obj),
                        obj: undefined,
                        _objType: this.getObjType(tree.obj),
                        _bomType: this.getObjType(tree.obj) == 'LGK__ConfigurationLineItem__c' ? tree.obj.LGK__Type__c : 'SALES',
                        _name: this.getName(tree.obj),
                        _parentName: parent ? parent._name : '',
                       
                        Revenue_Impact__c: description,
                        _quantity: description,
                        Description__c: description,
                        
                        [tree?.children?.length ? '_children' : '__bogus']: tree.children ? childRecs : null
                    })
                case 'SBQQ__QuoteLine__c':
                    
                    
                    return this.addLink({
                        ...tree,
                        ...this.flatten(tree.obj),
                        obj: undefined,
                        _objType: this.getObjType(tree.obj),
                        _bomType: this.getObjType(tree.obj) == 'LGK__ConfigurationLineItem__c' ? tree.obj.LGK__Type__c : 'SALES',
                        _name: this.getName(tree.obj),
                        _parentName: parent ? parent._name : '',
            
                        [tree?.children?.length ? '_children' : '__bogus']: tree.children ? childRecs : null
                    })
                case 'OpportunityLineItem':
                    
                    return this.addLink({
                        ...tree,
                        ...this.flatten(tree.obj),
                        obj: undefined,
                        _objType: this.getObjType(tree.obj),
                        _bomType: this.getObjType(tree.obj) == 'LGK__ConfigurationLineItem__c' ? tree.obj.LGK__Type__c : 'SALES',
                        _name: this.getName(tree.obj),
                        _parentName: parent ? parent._name : '',
                        _quantity: this.getFieldValue(tree.obj, 'Quantity'),
                        _listPrice: this.getFieldValue(tree.obj, 'ListPrice'),
                        _discount: this.getFieldValue(tree.obj, 'Discount'),
                        _totalPrice: this.getFieldValue(tree.obj, 'TotalPrice'),
            
                        [tree?.children?.length ? '_children' : '__bogus']: tree.children ? childRecs : null
                    })
                case 'SalesAgreementProduct':
                    
                    return this.addLink({
                        ...tree,
                        ...this.flatten(tree.obj),
                        obj: undefined,
                        _objType: this.getObjType(tree.obj),
                        _bomType: this.getObjType(tree.obj) == 'LGK__ConfigurationLineItem__c' ? tree.obj.LGK__Type__c : 'SALES',
                        _name: this.getName(tree.obj),
                        _parentName: parent ? parent._name : '',
                        _quantity: this.getFieldValue(tree.obj, 'TotalPlannedQuantity'),
                        _listPrice: this.getFieldValue(tree.obj, 'ListPrice'),
                        _discount: this.getFieldValue(tree.obj, 'DiscountPercentage'),
                        _totalPrice: this.getFieldValue(tree.obj, 'TotalPlannedAmount'),
            
                        [tree?.children?.length ? '_children' : '__bogus']: tree.children ? childRecs : null
                    })
                case 'OrderItem':
                    
                    return this.addLink({
                        ...tree,
                        ...this.flatten(tree.obj),
                        obj: undefined,
                        _objType: this.getObjType(tree.obj),
                        _bomType: this.getObjType(tree.obj) == 'LGK__ConfigurationLineItem__c' ? tree.obj.LGK__Type__c : 'SALES',
                        _name: this.getName(tree.obj),
                        _parentName: parent ? parent._name : '',
                        [tree?.children?.length ? '_children' : '__bogus']: tree.children ? childRecs : null
                    })
                // default:
                //     return this.addLink({
                //         ...tree,
                //         ...this.flatten(tree.obj),
                //         obj: undefined,
                //         _objType: this.getObjType(tree.obj),
                //         _bomType: this.getObjType(tree.obj) == 'LGK__ConfigurationLineItem__c' ? tree.obj.LGK__Type__c : 'SALES',
                //         _name: this.getName(tree.obj),
                //         _parentName: parent ? parent._name : '',
                //         [tree?.children?.length ? '_children' : '__bogus']: tree.children ? childRecs : null
                //     })
            }
        

            
    }));

    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        switch (action.name) {
            case 'edit_record':
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: row._objType,
                        actionName: 'edit',
                        recordId: row.Id
                    }
                });
                break;
            default:
        }
    }

    mfgItemsChanged(event) {
        this.includeMfgItems = event.target.checked;
    }


    configureProducts(event){
        var quoteURL = "/apex/sbqq__sb?scontrolCaching=1&id=" + this.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: quoteURL
            }
        });
    }
}