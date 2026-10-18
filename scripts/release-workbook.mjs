import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const modules=process.env.ARTIFACT_TOOL_NODE_MODULES;
const require=createRequire(modules ? path.join(modules,'..','package.json') : import.meta.url);
const {Workbook,SpreadsheetFile}=await import(pathToFileURL(require.resolve('@oai/artifact-tool')).href);
const data=JSON.parse(await fs.readFile(path.join(root,'docs/releases/history.json'),'utf8'));
const version=(await fs.readFile(path.join(root,'VERSION'),'utf8')).trim();
const build=Number((await fs.readFile(path.join(root,'BUILD_NUMBER'),'utf8')).trim());
const latest=data.releases.at(-1);
if(latest.version!==version || data.currentVersion!==version || latest.build!==build || latest.ref!==`v${version}`)throw Error('Release metadata mismatch');
const book=Workbook.create();
const history=book.worksheets.add('版本记录');
const detail=book.worksheets.add('发布明细');
const previewDir=path.join(root,'.test-output/release-record');
await fs.mkdir(previewDir,{recursive:true});
function base(sheet,title,lastCol,lastRow){
    sheet.showGridLines=false;
    sheet.getRange(`A1:${lastCol}${lastRow}`).format.font={name:'Arial',size:11,color:'#223047'};
    sheet.getRange(`A1:${lastCol}${lastRow}`).format.verticalAlignment='center';
    sheet.getRange('A2').values=[[title]];
    sheet.getRange('A2').format.font={name:'Arial',size:16,bold:true,color:'#253B64'};
    sheet.getRange(`A3:${lastCol}3`).format.borders={bottom:{style:'thin',color:'#253B64'}};
    sheet.getRange(`A5:${lastCol}5`).format={fill:'#253B64',font:{name:'Arial',size:11,bold:true,color:'#FFFFFF'},horizontalAlignment:'center',verticalAlignment:'center',rowHeight:28};
    sheet.freezePanes.freezeRows(5);
    sheet.freezePanes.freezeColumns(1);
}
function gitLink(ref){return ref ? `${data.repository}/${ref.startsWith('v')?'releases/tag':'commit'}/${ref}` : '无独立 Git 提交或标签';}
const historyEnd=5+data.releases.length;
const detailEnd=5+data.changes.length;
const noteRow=detailEnd+2;
base(history,'StreamDrop 版本记录','J',historyEnd);
history.getRange('A5:J5').values=[['版本','日期','变更级别','发布状态','构建号','Git 锚点','版本判断理由','主要变化','通过测试数','来源与限制']];
const rows=data.releases.map(r=>[r.version,new Date(`${r.date}T12:00:00Z`),r.kind,r.status,r.build,r.ref ?? '未独立提交',r.reason,r.summary,r.tests,`${gitLink(r.ref)}\n${r.limitations}`]);
history.getRange(`A6:J${historyEnd}`).values=rows;
history.getRange(`A6:J${historyEnd}`).format.wrapText=true;
history.getRange(`A6:J${historyEnd}`).format.rowHeight=80;
history.getRange(`B6:B${historyEnd}`).setNumberFormat('yyyy-mm-dd');
history.getRange(`E6:E${historyEnd}`).setNumberFormat('0');history.getRange(`I6:I${historyEnd}`).setNumberFormat('0');
const widths={A:105,B:110,C:100,D:145,E:75,F:195,G:245,H:300,I:95,J:365};
for(const [column,width] of Object.entries(widths))history.getRange(`${column}5:${column}${historyEnd}`).format.columnWidthPx=width;
history.getRange(`A${historyEnd}:J${historyEnd}`).format.fill='#EDF2FA';
base(detail,`StreamDrop ${version} 发布明细`,'E',noteRow+2);
detail.getRange('A5:E5').values=[['范围','变化说明','已执行验证','Git 锚点','来源']];
detail.getRange(`A6:E${detailEnd}`).values=data.changes.map(c=>[c.area,c.summary,c.verification,c.ref,gitLink(c.ref)]);
detail.getRange(`A6:E${detailEnd}`).format.wrapText=true;
detail.getRange(`A6:E${detailEnd}`).format.rowHeight=68;
for(const [column,width] of Object.entries({A:120,B:350,C:385,D:215,E:385}))detail.getRange(`${column}5:${column}${noteRow+2}`).format.columnWidthPx=width;
detail.getRange(`A${noteRow}`).values=[['兼容与限制']];detail.getRange(`A${noteRow}`).format.font={bold:true,color:'#253B64'};
detail.getRange(`B${noteRow}`).values=[['旧数据可读；不回填旧记录的播放观察。']];
detail.getRange(`B${noteRow+1}`).values=[['跨卷中断无法确认身份时，保留现场并报告未知。']];
detail.getRange(`B${noteRow+2}`).values=[['标签锚定最终提交；Excel 不写自身所属提交的 SHA。']];
detail.getRange(`B${noteRow}:C${noteRow+2}`).format.wrapText=true;detail.getRange(`A${noteRow}:E${noteRow+2}`).format.rowHeight=42;
book.recalculate();
for(const [name,range] of [['版本记录',`A5:J${historyEnd}`],['发布明细',`A5:E${noteRow+2}`]]){
    console.log((await book.inspect({kind:'table',range:`${name}!${range}`,include:'values',tableMaxRows:10,tableMaxCols:10,maxChars:1800})).ndjson);
    const preview=await book.render({sheetName:name,range:`A1:${range.split(':')[1]}`,scale:1,format:'png'});
    await fs.writeFile(path.join(previewDir,`${name}.png`),new Uint8Array(await preview.arrayBuffer()));
}
console.log((await book.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!',options:{useRegex:true,maxResults:20},maxChars:600})).ndjson);
const out=await SpreadsheetFile.exportXlsx(book);
const destination=path.join(root,'docs/releases/StreamDrop-version-history.xlsx');
await out.save(destination);
// The authoring tool may export an inspection sidecar; keep it local.
await fs.rename(destination+".inspect.ndjson",path.join(previewDir,"workbook.inspect.ndjson")).catch(error=>{if(error.code!=="ENOENT")throw error;});
console.log(`Exported ${destination}`);
