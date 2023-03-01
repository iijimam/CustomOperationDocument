Class CustomFS.MyOperations Extends HS.FHIRServer.Storage.BuiltInOperations
{

/// @API Enumerate the name and url of each Operation supported by this class
ClassMethod AddSupportedOperations(pMap As %DynamicObject)
{
    Do ##super(pMap)
    Do pMap.%Set("mydocument","http://myfhirserver/fhir/OperationDefinition/Composition-mydocument")
}

ClassMethod FHIRInstanceOpMydocument(pService As HS.FHIRServer.API.Service, pRequest As HS.FHIRServer.API.Data.Request, pResponse As HS.FHIRServer.API.Data.Response)
{
    ///RestClientクラスを利用してFHIRサーバへのアクセスを実行。指定された論理IDのCompositionリソースを取得する
    Set clientObj = ##class(HS.FHIRServer.RestClient.FHIRService).CreateInstance(pRequest.SessionApplication)
    Do clientObj.SetResponseFormat("JSON")
    set clientResponseComposition=clientObj.Read(pRequest.RequestMethod,pRequest.Type,pRequest.Id)

    // 1..1 Patientリソース Get
    set cj=clientResponseComposition.Json  //CompoistionリソースのJSON取得
    set ^iijima("json")=clientResponseComposition.Json.%ToJSON()
    set PatientID=$piece(cj.subject.reference,"/",2)
    set clientResponsePatient=clientObj.Read("GET","Patient",PatientID)
    // 0..1 Encounterリソース Get
    if $isobject(cj.encounter) {
        set EncounterID=$piece(cj.encounter.reference,"/",2)
        set clientResponseEncounter=clientObj.Read("GET","Encounter",EncounterID)
    }
    // 2..2 Practirioner/Organaization
    set iter=cj.author.%GetIterator()
    while iter.%GetNext(.key,.value) {
        set rname=$piece(value.reference,"/",1)
        set id=$piece(value.reference,"/",2)
        set clientResponseAuthor(key)=clientObj.Read("GET",rname,id)
    }
    // 1..1 OrganizationリソースGet
    set OrganizationID=$piece(cj.custodian.reference,"/",2)
    set clientResponseOrganization=clientObj.Read("GET","Organization",OrganizationID)

    // section.section以下のリソース取得
    // Composition.section.section().entry().reference / Composition.section.section().entry().type
    set ite1=cj.section.%GetIterator()
    while ite1.%GetNext(.k1,.v1) {
        set ite2=v1.section.%GetIterator()
        while ite2.%GetNext(.k2,.v2) {
            set ite3=v2.entry.%GetIterator()
            while ite3.%GetNext(.k3,.v3) {
                set rname=$piece(v3.reference,"/",1)
                set id=$piece(v3.reference,"/",2)
                #;Encounterのダブりをチェック
                if (rname="Encounter")&(id=EncounterID) {
                    continue
                }

                #;Conditionのダブりをチェック
                if (rname="Condition")&($data(condition(id))) {
                    continue
                }
                elseif (rname="Condition")&('$data(condition(id))) {
                    set condition(id)=""
                }
                set clientResponseSection(k1,k2,k3)=clientObj.Read("GET",rname,id)
            }
        }
    }
    //bundle作成
    set schema=##class(HS.FHIRServer.Schema).LoadSchema("HL7v40")
    //total0件のBundleできる
    set bundlejson=##class(HS.FHIRServer.Util.Bundle).CreateBundle({},"searchset",0,,schema)

    do bundlejson.entry.%Push(clientResponseComposition.Json)  //composition
    do bundlejson.entry.%Push(clientResponsePatient.Json)  //patient
    do bundlejson.entry.%Push(clientResponseOrganization.Json) // organization
    do bundlejson.entry.%Push(clientResponseEncounter.Json)  //encounter
    // author
    set cn=""
    for {
        set cn=$order(clientResponseAuthor(cn),1,obj)
        if cn="" quit
        do bundlejson.entry.%Push(obj.Json)
        kill obj
    }
    // section.sectionの中身
    set cn1=""
    for {
        set cn1=$order(clientResponseSection(cn1))
        if cn1="" quit
        set cn2=""
        for {
            set cn2=$order(clientResponseSection(cn1,cn2))
            if cn2="" quit
            set cn3=""
            for {
                set cn3=$order(clientResponseSection(cn1,cn2,cn3),1,obj)
                if cn3="" quit
                do bundlejson.entry.%Push(obj.Json)
                kill obj
            }

        }
    }

    //total件数の設定
    set bundlejson.total=bundlejson.entry.%Size()
    set pResponse.Json=bundlejson
}

}
