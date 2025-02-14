//
//  EncodedPolylineTests.swift
//  GeoJSONKitTurf
//
//  Created by Adrian Schönig on 14/2/2025.
//

#if canImport(Testing) && swift(>=6)
import Testing

import GeoJSONKit
import GeoJSONKitTurf

struct EncodedPolylineTests {
  
  @Test func testPalermoToRome() async throws {
    
    let polyline = "iasgFkxqpAbbCseDtrBmpDv_BgeEvtB_mDdjB_}Dz|@iuEjc@ihF`YcdFnn@__FjiAowErgAmoEvCwgFqOkbFiPghFoI{hFwNgfFcS}eFa}@e}EpRgyE|UslFfEgcFtWihFvSqhFbZi_Fm_AaoEknA}xDcBwiF}MsgF}IahF{EegFo_@kdFcNshFqYeiFmW}`FoVefF_NslFkyAeeEkrAilEw~AoeEyiAwpEcyBwpD{hAgqEc[weFyc@qbFiy@s|Ea`BkbEaUk`FvcAouEfiAaqE]{hFqf@uaFky@gsEymBavDytBkyDqaCw_DkbBu~De`Au_Fsj@wyEk\\agFrUycFfx@ozEdfBc`EhBarEclBiaEws@mtEgXijFMkjFeEmdFyn@mbFemAomE}fAwyE{yB_cDanDyy@_{C}nBu_DqlByaDqmBegDmuAitDkSknDwo@akAmjEyrAewEcsAavEwqAwfEo|AwlE_}AgbEkoC{iCmuCoyBahDu_BcsDcNcoDys@aqDq\\gwD{EyqD{h@uhD{eAmrDuIwuD^grD~VodDbvAizC`zBm`DncBgbDryBa~C{\\qoDomAwoDmg@euDwJ{nDlp@_fDvtAmeDx{AgoDbhAenDz]{pD~a@}kDf`AqjDdiA_oD~t@ymDlLizDlLicDxgAw_DnoBgmDnn@_sDtEyrDfTulDrl@ymDt_AolD~}@irDb{@ycD`~@ouDnr@agDxr@unD~q@anDbq@skDby@icDh_BmnD|z@meDxm@qpDzr@yxDj_@s|Cdl@krBxzDaqBzwDu{B~yCg_DnxB_gC~jCgpC`eC{cCb{C}qBluDijBlrD_|BxkDuiChlCotB|{CquBt|DutB~wDmeB`oDcbBnlE{mAjlEciC|dAygDhaAeqCvdCk_CljDe{BzcDg~B~`D{zBdeD{}Bh_Ds}BxlDivB|kD_nBvmDueBnaEugBtvDu~Ax}DgcCxdDgsBzeDgkBxyDu}AdcEgt@`wEqr@pgF{^v{E_PngF_W|gF}s@x~E}^tbFef@r`Fu`AhvEay@l}E}o@tdFqlAzgE}z@~xEmjBfvDmnAhmE}bBrvDwcAh_Fyp@h|EewAxbEosA|nDu|BlxCkjBv{D}gB|aEyeB`bEw`B||Dq~Az}D}tBznDy}BnwCmjB~vDoiB|_EigBjxDwgBr~D{_BlcE{uA`gEozAvcEylBhvDa{BhdDioBlqDulBf~D}_BtuDm_CfhDo~CrqAscC`lC_eCfzCuzBffDe|AnbE{mBhuDogClnCquC~pBo_Cr|CeqBhnDeiB`{DudBnzDeqBtnDuoBhpD_qBdrDwcBn}D{aBn`EefBdxDshBtzDumBdxDotAbeEazAzhEm_Bj}DcdB|zDylBpiDadBr|DqdBheEs_Bj~D{~A`cEiuAdlEm`AjsEsv@x`Feu@`mFcf@t}EmCfaF}s@jzDs{CfiBsuB|zCusB|jDedB|zDaxBjiDgNpR"
    
    let decoded = GeoJSON.LineString(encodedPolyline: polyline)
    #expect(decoded.positions.count == 256)
    
    #expect(decoded.encodedPolyline() == polyline)
  }
  
}

#endif
