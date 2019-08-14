extern(C):

import ast;

import core.stdc.stdio;
import core.stdc.stdlib;


int gen_llvm_ir(FILE* fp, Node* node, int* val_cnt)
{
    if(node.kind == NodeKind.NUM) {
        ++*val_cnt;
        fprintf(fp, "  %%%d = add i32 0, %d\n", *val_cnt, node.val);
        return *val_cnt;
    }

    int lhs_id = gen_llvm_ir(fp, node.lhs, val_cnt);
    int rhs_id = gen_llvm_ir(fp, node.rhs, val_cnt);

    ++*val_cnt;
    switch(node.kind) {
        case NodeKind.ADD:
            fprintf(fp, "  %%%d = add i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.SUB:
            fprintf(fp, "  %%%d = sub i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.MUL:
            fprintf(fp, "  %%%d = mul i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.DIV:
            fprintf(fp, "  %%%d = sdiv i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.EQ:
            fprintf(fp, "  %%%d = icmp eq i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.NE:
            fprintf(fp, "  %%%d = icmp ne i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.LT:
            fprintf(fp, "  %%%d = icmp slt i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.LE:
            fprintf(fp, "  %%%d = icmp sle i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.GT:
            fprintf(fp, "  %%%d = icmp sgt i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.GE:
            fprintf(fp, "  %%%d = icmp sge i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        default:
            fprintf(stderr, "サポートしていないノードの種類です\n");
            exit(1);
            break;

        Lzext:
            fprintf(fp, "  %%%d = zext i1 %%%d to i32\n", *val_cnt + 1, *val_cnt);
            ++*val_cnt;
            break;
    }

    return *val_cnt;
}
